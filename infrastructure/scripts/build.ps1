#Requires -Version 5.1
#Requires -Modules @{ModuleName='PSScriptAnalyzer';ModuleVersion='1.20.0'},@{ModuleName='platyPS';ModuleVersion='0.14.2'},@{ModuleName='Microsoft.PowerShell.Security';ModuleVersion='7.3.0'}

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [Parameter()]
    [switch]$Sign,

    [Parameter()]
    [switch]$Force
)

# Build script global variables
$script:BuildRoot = $PSScriptRoot/..
$script:OutputPath = "$BuildRoot/build"
$script:SourcePath = "$BuildRoot/src"
$script:DocsPath = "$BuildRoot/docs"
$script:SecurityPath = "$BuildRoot/security"
$script:CertificatePath = "$SecurityPath/certificates"

# Import build configuration
$script:BuildConfig = Get-Content -Path "$BuildRoot/config/build.settings.json" | ConvertFrom-Json

function Initialize-BuildEnvironment {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [string]$CertificatePath = $script:CertificatePath
    )

    Write-Verbose "Initializing build environment..."

    # Validate PowerShell version compatibility
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell version 5.1 or higher is required. Current version: $($PSVersionTable.PSVersion)"
    }

    # Create build directories if they don't exist
    $directories = @($OutputPath, $DocsPath, $SecurityPath)
    foreach ($dir in $directories) {
        if (!(Test-Path -Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    # Verify required modules
    foreach ($module in $BuildConfig.RequiredModules) {
        if (!(Get-Module -ListAvailable -Name $module.Name -ErrorAction SilentlyContinue)) {
            throw "Required module $($module.Name) version $($module.Version) is not installed"
        }
    }

    # Initialize security context
    if ($BuildConfig.Security.RequireCodeSigning) {
        if (!(Test-Path -Path $CertificatePath)) {
            throw "Code signing certificate path not found: $CertificatePath"
        }
        $cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | 
            Where-Object { $_.Thumbprint -eq $env:CODE_SIGNING_THUMBPRINT }
        if (!$cert) {
            throw "Code signing certificate not found with thumbprint: $env:CODE_SIGNING_THUMBPRINT"
        }
    }

    # Set security protocol
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function New-ModuleManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [Parameter(Mandatory)]
        [hashtable]$ManifestParams,
        
        [switch]$SignManifest
    )

    Write-Verbose "Generating module manifest..."

    # Validate manifest parameters
    $requiredParams = @('ModuleName', 'Version', 'Author', 'Description')
    foreach ($param in $requiredParams) {
        if (!$ManifestParams.ContainsKey($param)) {
            throw "Required manifest parameter missing: $param"
        }
    }

    # Generate manifest
    $manifestPath = Join-Path -Path $OutputPath -ChildPath "$($ManifestParams.ModuleName).psd1"
    
    # Add security-related manifest entries
    $ManifestParams['PowerShellVersion'] = $BuildConfig.PowerShellVersion
    $ManifestParams['RequiredModules'] = $BuildConfig.RequiredModules
    $ManifestParams['PrivateData'] = @{
        PSData = @{
            Tags = $BuildConfig.Distribution.PowerShellGallery.Tags
            ProjectUri = $BuildConfig.Distribution.PowerShellGallery.ProjectUri
            LicenseUri = $BuildConfig.Distribution.PowerShellGallery.LicenseUri
            IconUri = $BuildConfig.Distribution.PowerShellGallery.IconUri
            ReleaseNotes = "https://github.com/Blackpoint/PSCompassOne/releases"
        }
    }

    New-ModuleManifest -Path $manifestPath @ManifestParams

    # Validate manifest
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    if (!$manifest) {
        throw "Module manifest validation failed"
    }

    # Sign manifest if requested
    if ($SignManifest -and $BuildConfig.Security.RequireCodeSigning) {
        $cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | 
            Where-Object { $_.Thumbprint -eq $env:CODE_SIGNING_THUMBPRINT }
        Set-AuthenticodeSignature -FilePath $manifestPath -Certificate $cert -TimestampServer $BuildConfig.CodeSigning.TimestampServer
    }

    return $manifestPath
}

function Build-Documentation {
    [CmdletBinding()]
    param(
        [string]$Culture = 'en-US',
        [switch]$IncludeSecurity
    )

    Write-Verbose "Generating module documentation..."

    # Create documentation directory
    $docsOutputPath = Join-Path -Path $OutputPath -ChildPath $Culture
    New-Item -Path $docsOutputPath -ItemType Directory -Force | Out-Null

    # Generate markdown documentation
    $null = New-MarkdownHelp -Module $BuildConfig.ModuleName -OutputFolder $docsOutputPath -Force
    
    if ($IncludeSecurity) {
        # Add security documentation
        $securityDocsPath = Join-Path -Path $DocsPath -ChildPath "security"
        Copy-Item -Path "$securityDocsPath/*" -Destination $docsOutputPath -Recurse -Force
    }

    # Convert to MAML
    $null = New-ExternalHelp -Path $docsOutputPath -OutputPath $docsOutputPath -Force

    # Validate documentation
    $helpFiles = Get-ChildItem -Path $docsOutputPath -Filter "*.xml"
    if ($helpFiles.Count -eq 0) {
        throw "No help files were generated"
    }
}

function Build-Module {
    [CmdletBinding()]
    param(
        [switch]$Sign,
        [string]$Configuration = 'Release'
    )

    Write-Verbose "Building module with configuration: $Configuration"

    try {
        # Initialize build environment
        Initialize-BuildEnvironment -Force:$Force

        # Clean output directory
        if (Test-Path -Path $OutputPath) {
            Remove-Item -Path $OutputPath -Recurse -Force
        }
        New-Item -Path $OutputPath -ItemType Directory | Out-Null

        # Copy source files
        Copy-Item -Path "$SourcePath/*" -Destination $OutputPath -Recurse -Exclude @("*.Tests.ps1")

        # Generate manifest
        $manifestParams = @{
            ModuleName = $BuildConfig.ModuleName
            Version = $BuildConfig.Version
            Author = $BuildConfig.Author
            CompanyName = $BuildConfig.CompanyName
            Description = $BuildConfig.Description
            PowerShellVersion = $BuildConfig.PowerShellVersion
        }
        $manifestPath = New-ModuleManifest -OutputPath $OutputPath -ManifestParams $manifestParams -SignManifest:$Sign

        # Run PSScriptAnalyzer
        $analysisResults = Invoke-ScriptAnalyzer -Path $OutputPath -Recurse -Settings PSGallery
        if ($analysisResults) {
            throw "PSScriptAnalyzer found $($analysisResults.Count) issues"
        }

        # Build documentation
        Build-Documentation -IncludeSecurity

        # Sign module files if requested
        if ($Sign -and $BuildConfig.Security.RequireCodeSigning) {
            Get-ChildItem -Path $OutputPath -Recurse -Include @("*.ps1", "*.psm1", "*.psd1") | ForEach-Object {
                $cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | 
                    Where-Object { $_.Thumbprint -eq $env:CODE_SIGNING_THUMBPRINT }
                Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert -TimestampServer $BuildConfig.CodeSigning.TimestampServer
            }
        }

        # Validate build outputs
        if ($BuildConfig.Security.ValidateHashOnBuild) {
            Get-ChildItem -Path $OutputPath -Recurse -File | ForEach-Object {
                $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256
                Add-Content -Path "$OutputPath\checksums.txt" -Value "$($hash.Hash) $($_.Name)"
            }
        }

        Write-Verbose "Module build completed successfully"
    }
    catch {
        Write-Error "Module build failed: $_"
        throw
    }
}

# Export the main build function
Export-ModuleMember -Function Build-Module