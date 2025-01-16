#Requires -Version 7.0
#Requires -Modules PowerShellGet, Microsoft.PowerShell.Security
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

# Import required modules
Import-Module PowerShellGet -Version 2.2.5 # PowerShell module publishing cmdlets
Import-Module Microsoft.PowerShell.Security -Version 7.0.0 # Security and credential management

# Set strict error handling
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Import local dependencies
. "$PSScriptRoot/sign.ps1"

# Initialize script-level variables
$script:PublishConfig = Get-Content -Path "$PSScriptRoot/../config/publish.settings.json" | ConvertFrom-Json
$script:MaxRetryAttempts = 3
$script:RetryDelaySeconds = 30
$script:WorkingDir = Join-Path $env:TEMP "PSCompassOne_Publish_$(Get-Date -Format 'yyyyMMddHHmmss')"
$script:LogFile = Join-Path $PSScriptRoot "../logs/publish_$(Get-Date -Format 'yyyyMMddHHmmss').log"

function Initialize-PublishEnvironment {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "Initializing publishing environment..."
        
        # Create working and log directories
        New-Item -ItemType Directory -Path $script:WorkingDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $script:LogFile -Parent) -Force | Out-Null

        # Validate configuration
        if (-not $script:PublishConfig.PowerShellGallery -or -not $script:PublishConfig.GitHubPackages) {
            throw "Invalid publish configuration: Missing required sections"
        }

        # Verify API credentials
        $galleryKey = $env:POWERSHELL_GALLERY_API_KEY
        $githubToken = $env:GITHUB_TOKEN

        if ($script:PublishConfig.PowerShellGallery.Enabled -and -not $galleryKey) {
            throw "PowerShell Gallery API key not found in environment"
        }

        if ($script:PublishConfig.GitHubPackages.Enabled -and -not $githubToken) {
            throw "GitHub token not found in environment"
        }

        # Test network connectivity
        $endpoints = @()
        if ($script:PublishConfig.PowerShellGallery.Enabled) {
            $endpoints += "powershellgallery.com"
        }
        if ($script:PublishConfig.GitHubPackages.Enabled) {
            $endpoints += "nuget.pkg.github.com"
        }

        foreach ($endpoint in $endpoints) {
            $test = Test-NetConnection -ComputerName $endpoint -Port 443
            if (-not $test.TcpTestSucceeded) {
                throw "Failed to connect to $endpoint"
            }
        }

        Write-Verbose "Publishing environment initialized successfully"
        return @{
            WorkingDir = $script:WorkingDir
            LogFile = $script:LogFile
            GalleryEnabled = $script:PublishConfig.PowerShellGallery.Enabled
            GitHubEnabled = $script:PublishConfig.GitHubPackages.Enabled
        }
    }
    catch {
        Write-Error "Failed to initialize publishing environment: $_"
        throw
    }
}

function Publish-ToPowerShellGallery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath,
        
        [Parameter(Mandatory)]
        [securestring]$ApiKey,
        
        [Parameter()]
        [hashtable]$Options
    )

    try {
        Write-Verbose "Publishing to PowerShell Gallery..."

        # Validate module manifest
        $manifest = Test-ModuleManifest -Path (Join-Path $ModulePath "*.psd1") -ErrorAction Stop
        Write-Verbose "Module version: $($manifest.Version)"

        # Create temporary publishing directory
        $publishDir = Join-Path $script:WorkingDir "gallery_publish"
        Copy-Item -Path $ModulePath -Destination $publishDir -Recurse

        # Publish with retry logic
        $attempt = 1
        $published = $false

        do {
            try {
                $params = @{
                    Path = $publishDir
                    NuGetApiKey = $ApiKey
                    Repository = $script:PublishConfig.PowerShellGallery.RepositoryName
                    Force = $true
                    ErrorAction = 'Stop'
                }

                Publish-Module @params
                $published = $true
                break
            }
            catch {
                Write-Warning "Attempt $attempt failed: $_"
                if ($attempt -lt $script:MaxRetryAttempts) {
                    Start-Sleep -Seconds ($script:RetryDelaySeconds * $attempt)
                }
                $attempt++
            }
        } while ($attempt -le $script:MaxRetryAttempts)

        if (-not $published) {
            throw "Failed to publish to PowerShell Gallery after $script:MaxRetryAttempts attempts"
        }

        # Verify publication
        $verifyAttempts = 3
        do {
            Start-Sleep -Seconds 30
            $published = Find-Module -Name $manifest.Name -RequiredVersion $manifest.Version -ErrorAction SilentlyContinue
            $verifyAttempts--
        } while (-not $published -and $verifyAttempts -gt 0)

        if (-not $published) {
            throw "Module publication verification failed"
        }

        Write-Verbose "Successfully published to PowerShell Gallery"
        return $true
    }
    catch {
        Write-Error "Failed to publish to PowerShell Gallery: $_"
        throw
    }
    finally {
        if (Test-Path $publishDir) {
            Remove-Item -Path $publishDir -Recurse -Force
        }
    }
}

function Publish-ToGitHubPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath,
        
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Credentials,
        
        [Parameter()]
        [hashtable]$Options
    )

    try {
        Write-Verbose "Publishing to GitHub Packages..."

        # Validate package
        $manifest = Test-ModuleManifest -Path (Join-Path $PackagePath "*.psd1") -ErrorAction Stop
        $version = $manifest.Version
        $packageName = $manifest.Name

        # Create NuGet package
        $nugetDir = Join-Path $script:WorkingDir "nuget_publish"
        New-Item -ItemType Directory -Path $nugetDir -Force | Out-Null

        $nuspec = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2011/08/nuspec.xsd">
    <metadata>
        <id>$packageName</id>
        <version>$version</version>
        <authors>Blackpoint</authors>
        <owners>Blackpoint</owners>
        <requireLicenseAcceptance>false</requireLicenseAcceptance>
        <description>$($manifest.Description)</description>
        <copyright>Copyright © $(Get-Date -Format yyyy) Blackpoint</copyright>
        <tags>PSModule PowerShell CompassOne Security</tags>
    </metadata>
</package>
"@

        $nuspecPath = Join-Path $nugetDir "$packageName.nuspec"
        Set-Content -Path $nuspecPath -Value $nuspec

        Copy-Item -Path $PackagePath -Destination (Join-Path $nugetDir "content") -Recurse

        # Pack and publish
        $attempt = 1
        $published = $false

        do {
            try {
                # Pack
                $packOutput = nuget pack $nuspecPath -OutputDirectory $nugetDir
                if (-not $?) { throw "NuGet pack failed" }

                # Push
                $pushParams = @(
                    'push'
                    (Get-ChildItem -Path $nugetDir -Filter "*.nupkg").FullName
                    $Credentials.GetNetworkCredential().Password
                    '-Source'
                    $script:PublishConfig.GitHubPackages.RepositoryUrl
                    '-SkipDuplicate'
                )
                
                $pushOutput = nuget $pushParams
                if (-not $?) { throw "NuGet push failed" }

                $published = $true
                break
            }
            catch {
                Write-Warning "Attempt $attempt failed: $_"
                if ($attempt -lt $script:MaxRetryAttempts) {
                    Start-Sleep -Seconds ($script:RetryDelaySeconds * $attempt)
                }
                $attempt++
            }
        } while ($attempt -le $script:MaxRetryAttempts)

        if (-not $published) {
            throw "Failed to publish to GitHub Packages after $script:MaxRetryAttempts attempts"
        }

        Write-Verbose "Successfully published to GitHub Packages"
        return $true
    }
    catch {
        Write-Error "Failed to publish to GitHub Packages: $_"
        throw
    }
    finally {
        if (Test-Path $nugetDir) {
            Remove-Item -Path $nugetDir -Recurse -Force
        }
    }
}

function Send-PublishNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status,
        
        [Parameter(Mandatory)]
        [hashtable]$Details,
        
        [Parameter()]
        [string[]]$Recipients
    )

    try {
        Write-Verbose "Sending publish notifications..."

        # Email notifications
        if ($script:PublishConfig.Notifications.Email.Enabled) {
            $emailParams = @{
                From = $script:PublishConfig.Notifications.Email.FromAddress
                To = $script:PublishConfig.Notifications.Email.Recipients
                Subject = "PSCompassOne Module Publication - $Status"
                Body = $Details | ConvertTo-Json -Depth 10
                SmtpServer = $env:SMTP_SERVER
                UseSSL = $true
                Credential = (Get-Credential -UserName $env:SMTP_USER)
            }
            Send-MailMessage @emailParams
        }

        # Teams notifications
        if ($script:PublishConfig.Notifications.Teams.Enabled) {
            $teamsCard = @{
                "@type" = "MessageCard"
                "@context" = "http://schema.org/extensions"
                "summary" = "Module Publication Status"
                "themeColor" = if ($Status -eq "Success") { "00ff00" } else { "ff0000" }
                "title" = "PSCompassOne Module Publication - $Status"
                "sections" = @(
                    @{
                        "facts" = $Details.GetEnumerator() | ForEach-Object {
                            @{
                                "name" = $_.Key
                                "value" = $_.Value
                            }
                        }
                    }
                )
            }

            $webhookUrl = $env:TEAMS_WEBHOOK_URL
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Body ($teamsCard | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        }

        # GitHub notifications
        if ($script:PublishConfig.Notifications.GitHub.CreateRelease) {
            $releaseParams = @{
                Uri = "https://api.github.com/repos/blackpoint/pscompassone/releases"
                Method = 'POST'
                Headers = @{
                    Authorization = "token $env:GITHUB_TOKEN"
                    Accept = 'application/vnd.github.v3+json'
                }
                Body = @{
                    tag_name = "v$($Details.Version)"
                    name = "Release v$($Details.Version)"
                    body = $Details.ReleaseNotes
                    draft = $false
                    prerelease = $false
                } | ConvertTo-Json
                ContentType = 'application/json'
            }
            Invoke-RestMethod @releaseParams
        }

        Write-Verbose "Successfully sent notifications"
    }
    catch {
        Write-Warning "Failed to send notifications: $_"
        # Don't throw - notifications shouldn't block the publishing process
    }
}

function Publish-PSCompassOneModule {
    [CmdletBinding()]
    param()

    try {
        # Initialize environment
        $env = Initialize-PublishEnvironment

        # Create session log
        Start-Transcript -Path $env.LogFile -Append

        Write-Verbose "Starting module publication process..."

        # Build paths
        $modulePath = Resolve-Path "$PSScriptRoot/../../src"
        $manifest = Test-ModuleManifest -Path (Join-Path $modulePath "*.psd1")
        
        # Sign module files
        Write-Verbose "Signing module files..."
        Sign-ModuleFiles

        # Track publication results
        $results = @{
            Version = $manifest.Version
            StartTime = Get-Date
            PowerShellGallery = "Skipped"
            GitHubPackages = "Skipped"
            Errors = @()
        }

        # Publish to PowerShell Gallery
        if ($env.GalleryEnabled) {
            try {
                $galleryKey = ConvertTo-SecureString $env:POWERSHELL_GALLERY_API_KEY -AsPlainText -Force
                $published = Publish-ToPowerShellGallery -ModulePath $modulePath -ApiKey $galleryKey
                $results.PowerShellGallery = if ($published) { "Success" } else { "Failed" }
            }
            catch {
                $results.PowerShellGallery = "Failed"
                $results.Errors += "PowerShell Gallery: $_"
            }
        }

        # Publish to GitHub Packages
        if ($env.GitHubEnabled) {
            try {
                $githubCred = New-Object System.Management.Automation.PSCredential (
                    "github",
                    (ConvertTo-SecureString $env:GITHUB_TOKEN -AsPlainText -Force)
                )
                $published = Publish-ToGitHubPackages -PackagePath $modulePath -Credentials $githubCred
                $results.GitHubPackages = if ($published) { "Success" } else { "Failed" }
            }
            catch {
                $results.GitHubPackages = "Failed"
                $results.Errors += "GitHub Packages: $_"
            }
        }

        # Calculate overall status
        $results.EndTime = Get-Date
        $results.Duration = $results.EndTime - $results.StartTime
        $results.Status = if ($results.Errors.Count -eq 0) { "Success" } else { "Failed" }

        # Send notifications
        Send-PublishNotification -Status $results.Status -Details $results

        # Output results
        $results | ConvertTo-Json -Depth 10 | Write-Verbose

        if ($results.Status -eq "Failed") {
            throw "Publication failed with errors: $($results.Errors -join '; ')"
        }

        Write-Verbose "Module publication completed successfully"
    }
    catch {
        Write-Error "Module publication failed: $_"
        throw
    }
    finally {
        Stop-Transcript
        if (Test-Path $script:WorkingDir) {
            Remove-Item -Path $script:WorkingDir -Recurse -Force
        }
    }
}

# Export the main publishing function
Export-ModuleMember -Function Publish-PSCompassOneModule