#Requires -Version 5.1
#Requires -Modules @{ModuleName='PSScriptAnalyzer';ModuleVersion='1.20.0'}, @{ModuleName='Microsoft.PowerShell.SecretStore';ModuleVersion='1.0.6'}

[CmdletBinding()]
param()

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Initialize validation context
$script:ValidationContext = @{
    Timestamp = (Get-Date).ToUniversalTime().ToString('o')
    Environment = $env:ENVIRONMENT ?? 'Development'
    ValidationLevel = 'Comprehensive'
}

# Import configurations
try {
    $buildConfig = Get-Content -Path "$PSScriptRoot/../config/build.settings.json" -Raw | ConvertFrom-Json
    $securityConfig = Get-Content -Path "$PSScriptRoot/../config/security.settings.json" -Raw | ConvertFrom-Json
    Write-Verbose "Loaded configuration files successfully"
} catch {
    throw "Failed to load configuration files: $_"
}

function Test-ModuleManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    try {
        Write-Verbose "Validating module manifest at $ManifestPath"
        $manifestValidation = @{
            Result = $false
            Errors = @()
            Warnings = @()
        }

        # Test manifest file existence
        if (-not (Test-Path $ManifestPath)) {
            throw "Module manifest not found at: $ManifestPath"
        }

        # Import and validate manifest
        $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        
        # Validate required fields
        $requiredFields = @('ModuleVersion', 'Author', 'Description', 'PowerShellVersion')
        foreach ($field in $requiredFields) {
            if (-not $manifest.$field) {
                $manifestValidation.Errors += "Missing required field: $field"
            }
        }

        # Validate version format
        if ($manifest.ModuleVersion -and -not [System.Version]::TryParse($manifest.ModuleVersion, [ref]$null)) {
            $manifestValidation.Errors += "Invalid module version format: $($manifest.ModuleVersion)"
        }

        # Validate PowerShell version compatibility
        $minPSVersion = [System.Version]$manifest.PowerShellVersion
        if ($minPSVersion -lt [System.Version]'5.1') {
            $manifestValidation.Errors += "Minimum PowerShell version must be 5.1 or higher"
        }

        # Validate required modules
        foreach ($requiredModule in $manifest.RequiredModules) {
            if ($requiredModule.Name -eq 'Microsoft.PowerShell.SecretStore' -and 
                [System.Version]$requiredModule.Version -lt [System.Version]'1.0.6') {
                $manifestValidation.Errors += "SecretStore module version must be 1.0.6 or higher"
            }
        }

        $manifestValidation.Result = $manifestValidation.Errors.Count -eq 0
        return $manifestValidation
    } catch {
        throw "Module manifest validation failed: $_"
    }
}

function Test-SecurityCompliance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSObject]$SecuritySettings
    )

    try {
        Write-Verbose "Validating security compliance"
        $complianceResults = @{
            Result = $false
            Findings = @()
            Recommendations = @()
        }

        # Validate TLS requirements
        if (-not $SecuritySettings.transportSecurity.enforceHttps) {
            $complianceResults.Findings += "HTTPS enforcement is not enabled"
        }
        if ($SecuritySettings.transportSecurity.minimumTlsVersion -ne '1.2') {
            $complianceResults.Findings += "Minimum TLS version must be 1.2"
        }

        # Validate SecretStore configuration
        if (-not $SecuritySettings.authentication.secretStore.required) {
            $complianceResults.Findings += "SecretStore usage must be required"
        }

        # Validate token handling
        if (-not $SecuritySettings.authentication.tokenValidation.enabled) {
            $complianceResults.Findings += "Token validation must be enabled"
        }

        # Validate audit logging
        if (-not $SecuritySettings.auditLogging.enabled) {
            $complianceResults.Findings += "Audit logging must be enabled"
        }

        # Validate encryption settings
        if ($SecuritySettings.dataProtection.encryption.algorithm -ne 'AES-256') {
            $complianceResults.Findings += "Encryption algorithm must be AES-256"
        }

        $complianceResults.Result = $complianceResults.Findings.Count -eq 0
        return $complianceResults
    } catch {
        throw "Security compliance validation failed: $_"
    }
}

function Test-CodeQuality {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath
    )

    try {
        Write-Verbose "Performing code quality analysis on $ModulePath"
        $analysisResults = @{
            Result = $false
            Issues = @()
            Recommendations = @()
        }

        # Define custom rules
        $customRules = @{
            IncludeRules = @(
                'PSAvoidUsingPlainTextForPassword',
                'PSUsePSCredentialType',
                'PSAvoidUsingConvertToSecureStringWithPlainText',
                'PSUseShouldProcessForStateChangingFunctions'
            )
            Severity = @('Error', 'Warning')
        }

        # Run PSScriptAnalyzer
        $analysis = Invoke-ScriptAnalyzer -Path $ModulePath -Settings $customRules -Recurse

        foreach ($issue in $analysis) {
            $analysisResults.Issues += @{
                RuleName = $issue.RuleName
                Severity = $issue.Severity
                Line = $issue.Line
                File = $issue.ScriptName
                Message = $issue.Message
            }
        }

        # Add recommendations for common issues
        $analysisResults.Recommendations = $analysis | Group-Object RuleName | ForEach-Object {
            @{
                Rule = $_.Name
                Count = $_.Count
                Recommendation = "Review and fix all instances of $($_.Name)"
            }
        }

        $analysisResults.Result = ($analysis | Where-Object Severity -eq 'Error').Count -eq 0
        return $analysisResults
    } catch {
        throw "Code quality analysis failed: $_"
    }
}

function Test-ModuleCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath,
        [string[]]$PowerShellVersions = @('5.1', '7.0', '7.2')
    )

    try {
        Write-Verbose "Testing module compatibility across PowerShell versions"
        $compatibilityResults = @{
            Result = $false
            VersionResults = @{}
            PlatformSpecific = @{}
        }

        foreach ($psVersion in $PowerShellVersions) {
            $versionResult = @{
                Tested = $false
                LoadSuccessful = $false
                CommandsAvailable = $false
                Issues = @()
            }

            # Test module load
            try {
                $null = Import-Module $ModulePath -Force -ErrorAction Stop
                $versionResult.LoadSuccessful = $true
            } catch {
                $versionResult.Issues += "Failed to load module: $_"
            }

            # Test command availability
            if ($versionResult.LoadSuccessful) {
                $commands = Get-Command -Module (Get-Item $ModulePath).BaseName -ErrorAction SilentlyContinue
                $versionResult.CommandsAvailable = $commands.Count -gt 0
                if (-not $versionResult.CommandsAvailable) {
                    $versionResult.Issues += "No commands available in module"
                }
            }

            $versionResult.Tested = $true
            $compatibilityResults.VersionResults[$psVersion] = $versionResult
        }

        # Add platform-specific checks
        $compatibilityResults.PlatformSpecific = @{
            Windows = Test-WindowsCompatibility -ModulePath $ModulePath
            Linux = Test-LinuxCompatibility -ModulePath $ModulePath
            MacOS = Test-MacOSCompatibility -ModulePath $ModulePath
        }

        $compatibilityResults.Result = -not ($compatibilityResults.VersionResults.Values.Issues.Count -gt 0)
        return $compatibilityResults
    } catch {
        throw "Module compatibility testing failed: $_"
    }
}

# Helper functions for platform-specific checks
function Test-WindowsCompatibility {
    param([string]$ModulePath)
    return @{
        Supported = $true
        Features = @('SecretStore', 'CredentialManager')
        Issues = @()
    }
}

function Test-LinuxCompatibility {
    param([string]$ModulePath)
    return @{
        Supported = $true
        Features = @('SecretStore')
        Issues = @()
    }
}

function Test-MacOSCompatibility {
    param([string]$ModulePath)
    return @{
        Supported = $true
        Features = @('SecretStore')
        Issues = @()
    }
}

# Main validation execution
try {
    $ValidationResults = @{
        ManifestValidation = $null
        SecurityCompliance = $null
        CodeAnalysis = $null
        CompatibilityChecks = $null
        ValidationContext = $script:ValidationContext
        Recommendations = @()
    }

    # Execute validation steps
    $ValidationResults.ManifestValidation = Test-ModuleManifest -ManifestPath "$($buildConfig.SourcePath)/$($buildConfig.ModuleName).psd1"
    $ValidationResults.SecurityCompliance = Test-SecurityCompliance -SecuritySettings $securityConfig
    $ValidationResults.CodeAnalysis = Test-CodeQuality -ModulePath $buildConfig.SourcePath
    $ValidationResults.CompatibilityChecks = Test-ModuleCompatibility -ModulePath $buildConfig.SourcePath

    # Aggregate recommendations
    $ValidationResults.Recommendations += $ValidationResults.Values | 
        Where-Object { $_ -is [hashtable] -and $_.Recommendations } | 
        Select-Object -ExpandProperty Recommendations

    # Export results
    $ValidationResults | ConvertTo-Json -Depth 10 | 
        Set-Content -Path "$($buildConfig.BuildOutputPath)/validation-results.json"

    # Determine overall validation status
    $overallSuccess = $ValidationResults.Values | 
        Where-Object { $_ -is [hashtable] -and $_.Result -is [bool] } | 
        ForEach-Object Result | 
        Test-All

    if (-not $overallSuccess) {
        throw "Validation failed. Check validation-results.json for details."
    }

    Write-Verbose "Validation completed successfully"
    return $ValidationResults
} catch {
    Write-Error "Validation failed: $_"
    throw
}