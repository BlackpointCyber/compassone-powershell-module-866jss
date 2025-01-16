#Requires -Version 5.1
#Requires -Modules @{ ModuleName="Microsoft.PowerShell.SecretStore"; ModuleVersion="1.0.6" }

using namespace System.IO
using namespace System.Security.Cryptography
using namespace System.IO.Compression

# Import required .NET assemblies
Add-Type -AssemblyName 'System.IO.Compression.FileSystem' # Version 4.3.0
Add-Type -AssemblyName 'System.Security.Cryptography' # Version 4.3.0

function New-ModulePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$BuildConfig,

        [Parameter()]
        [switch]$EnterpriseDeployment
    )

    try {
        # Initialize build context
        $moduleName = $BuildConfig.ModuleName
        $version = $BuildConfig.Version
        $buildPath = Join-Path $OutputPath $moduleName
        $packagePath = Join-Path $OutputPath "$moduleName.$version.nupkg"

        # Create build directory if it doesn't exist
        if (-not (Test-Path $buildPath)) {
            New-Item -Path $buildPath -ItemType Directory -Force | Out-Null
        }

        Write-Verbose "Creating module package for $moduleName version $version"

        # Validate module manifest
        $manifestValidation = Test-ModuleManifest -ManifestPath (Join-Path $buildPath "$moduleName.psd1") -SecurityPolicy $BuildConfig.Security
        if (-not $manifestValidation.IsValid) {
            throw "Module manifest validation failed: $($manifestValidation.Errors -join '; ')"
        }

        # Create NuGet package
        $nuspecPath = Join-Path $buildPath "$moduleName.nuspec"
        $nugetPackage = New-NuGetPackage -NuSpecPath $nuspecPath -OutputPath $packagePath -EnterpriseConfig $BuildConfig.Distribution.Enterprise

        # Perform package validation
        $validationResults = @{
            ManifestValidation = $manifestValidation
            PackageValidation = $nugetPackage.ValidationResults
            SecurityChecks = @{
                CodeSigned = Test-CodeSigning -Path $packagePath -Policy $BuildConfig.CodeSigning
                TlsCompliance = $BuildConfig.Security.MinimumTLSVersion -eq '1.2'
                HashValidation = Test-FileHash -Path $packagePath -Algorithm SHA256
            }
        }

        # Return package information
        $packageInfo = [PSCustomObject]@{
            PSTypeName = 'PSCompassOne.ModulePackage'
            Path = $packagePath
            Version = $version
            ValidationResults = $validationResults
        }

        return $packageInfo
    }
    catch {
        Write-Error "Failed to create module package: $_"
        throw
    }
}

function Test-ModuleManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$SecurityPolicy
    )

    try {
        # Verify manifest file exists
        if (-not (Test-Path $ManifestPath)) {
            throw "Manifest file not found: $ManifestPath"
        }

        # Import and validate manifest
        $manifest = Import-PowerShellDataFile -Path $ManifestPath
        $validationResults = @{
            IsValid = $true
            Errors = @()
        }

        # Validate required fields
        $requiredFields = @('RootModule', 'ModuleVersion', 'GUID', 'Author', 'Description')
        foreach ($field in $requiredFields) {
            if (-not $manifest.ContainsKey($field)) {
                $validationResults.Errors += "Missing required field: $field"
                $validationResults.IsValid = $false
            }
        }

        # Validate PowerShell version compatibility
        if ([Version]$manifest.PowerShellVersion -lt [Version]'5.1') {
            $validationResults.Errors += "Minimum PowerShell version must be 5.1 or higher"
            $validationResults.IsValid = $false
        }

        # Validate security requirements
        if ($SecurityPolicy.RequireCodeSigning -and -not $manifest.PrivateData.PSData.SignatureRequired) {
            $validationResults.Errors += "Code signing is required but not enforced in manifest"
            $validationResults.IsValid = $false
        }

        return [PSCustomObject]$validationResults
    }
    catch {
        Write-Error "Module manifest validation failed: $_"
        throw
    }
}

function New-NuGetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NuSpecPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$EnterpriseConfig
    )

    try {
        # Validate NuSpec file
        if (-not (Test-Path $NuSpecPath)) {
            throw "NuSpec file not found: $NuSpecPath"
        }

        # Load NuSpec template
        [xml]$nuspec = Get-Content -Path $NuSpecPath
        
        # Apply enterprise-specific configurations
        if ($EnterpriseConfig.Enabled) {
            $nuspec.package.metadata.requireLicenseAcceptance = $EnterpriseConfig.RequireApproval.ToString().ToLower()
            if ($EnterpriseConfig.RequireCodeSigning) {
                $nuspec.package.metadata.SetAttribute("signed", "true")
            }
        }

        # Create package directory structure
        $tempPath = Join-Path ([Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

        try {
            # Copy files according to NuSpec
            foreach ($file in $nuspec.package.files.file) {
                $sourcePath = $file.src
                $targetPath = Join-Path $tempPath $file.target
                
                # Ensure target directory exists
                $targetDir = [Path]::GetDirectoryName($targetPath)
                if (-not (Test-Path $targetDir)) {
                    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                }

                # Copy files with verification
                Copy-Item -Path $sourcePath -Destination $targetPath -Force
                if (-not (Test-Path $targetPath)) {
                    throw "Failed to copy file: $sourcePath"
                }
            }

            # Create package
            [ZipFile]::CreateFromDirectory($tempPath, $OutputPath, [CompressionLevel]::Optimal, $false)

            # Validate package
            $validationResults = @{
                FileCount = (Get-ChildItem -Path $tempPath -Recurse -File).Count
                Size = (Get-Item $OutputPath).Length
                Hash = (Get-FileHash -Path $OutputPath -Algorithm SHA256).Hash
            }

            return [PSCustomObject]@{
                Path = $OutputPath
                ValidationResults = $validationResults
            }
        }
        finally {
            # Cleanup temporary directory
            if (Test-Path $tempPath) {
                Remove-Item -Path $tempPath -Recurse -Force
            }
        }
    }
    catch {
        Write-Error "Failed to create NuGet package: $_"
        throw
    }
}

# Helper function to test code signing
function Test-CodeSigning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [hashtable]$Policy
    )

    if (-not $Policy.Required) { return $true }

    $signature = Get-AuthenticodeSignature -FilePath $Path
    return $signature.Status -eq 'Valid' -and $signature.SignerCertificate.Thumbprint -eq $env:CODE_SIGNING_THUMBPRINT
}

# Helper function to test file hash
function Test-FileHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Algorithm
    )

    $hash = Get-FileHash -Path $Path -Algorithm $Algorithm
    return $hash -ne $null -and $hash.Hash.Length -gt 0
}

# Export the module package path and validation results
Export-ModuleMember -Variable ModulePackagePath