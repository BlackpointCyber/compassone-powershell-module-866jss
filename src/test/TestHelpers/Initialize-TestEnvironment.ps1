#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

using module Microsoft.PowerShell.SecretStore # Version 1.0.6

# Global test environment paths
$script:TestModulePath = "$PSScriptRoot/../../PSCompassOne"
$script:TestConfigPath = "$PSScriptRoot/../TestConfig"
$script:TestDataPath = "$PSScriptRoot/../TestData"
$script:PlatformConfig = @{
    Windows = @{
        PathSeparator = '\'
        TempPath = "$env:TEMP\PSCompassOne"
        SecretStoreScope = 'CurrentUser'
    }
    Linux = @{
        PathSeparator = '/'
        TempPath = '/tmp/PSCompassOne'
        SecretStoreScope = 'CurrentUser'
    }
    MacOS = @{
        PathSeparator = '/'
        TempPath = '/tmp/PSCompassOne'
        SecretStoreScope = 'CurrentUser'
    }
}

function Initialize-TestEnvironment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [string]$TestPath,

        [Parameter()]
        [switch]$UseMocks,

        [Parameter()]
        [hashtable]$CoverageSettings,

        [Parameter()]
        [switch]$CrossPlatform
    )

    # Load test settings
    $testSettings = Get-Content -Path "$TestConfigPath/test.settings.json" | ConvertFrom-Json
    
    # Detect current platform
    $currentPlatform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
    $platformSettings = $script:PlatformConfig[$currentPlatform]

    # Initialize test environment configuration
    $testEnvironment = @{
        Platform = $currentPlatform
        PowerShellVersion = $PSVersionTable.PSVersion
        ModulePath = $ModulePath
        TestPath = $TestPath
        TempPath = $platformSettings.TempPath
        UseMocks = $UseMocks.IsPresent
        CrossPlatform = $CrossPlatform.IsPresent
        Settings = $testSettings
    }

    try {
        # Create test directories
        $testDirs = Initialize-TestDirectories -BasePath $testEnvironment.TempPath -Platform $currentPlatform
        $testEnvironment.Directories = $testDirs

        # Configure SecretStore
        $null = Initialize-SecretStore -Scope $platformSettings.SecretStoreScope -Password (ConvertTo-SecureString -String "TestPassword123!" -AsPlainText -Force)

        # Set up mock environment if requested
        if ($UseMocks) {
            $mockClient = New-MockHttpClient -Configuration @{
                EnableRequestLogging = $true
                ValidateResponses = $true
                SimulateLatency = $false
            }
            $testEnvironment.MockClient = $mockClient

            # Load mock responses
            $mockResponses = @{
                Assets = Get-Content "$PSScriptRoot/../Mocks/AssetData.json" | ConvertFrom-Json
                Findings = Get-Content "$PSScriptRoot/../Mocks/FindingData.json" | ConvertFrom-Json
                ApiResponses = Get-Content "$PSScriptRoot/../Mocks/ApiResponses.json" | ConvertFrom-Json
            }
            $testEnvironment.MockData = $mockResponses
        }

        # Configure Pester
        $pesterConfig = New-PSCompassOnePesterConfig
        if ($CoverageSettings) {
            $pesterConfig.CodeCoverage.MinimumThreshold = $CoverageSettings.MinimumThreshold
            $pesterConfig.CodeCoverage.CoveragePercentTarget = $CoverageSettings.TargetPercent
            $pesterConfig.CodeCoverage.OutputPath = Join-Path $testDirs.OutputPath "coverage"
        }
        $testEnvironment.PesterConfig = $pesterConfig

        # Set environment variables for cross-platform testing
        if ($CrossPlatform) {
            $env:PSCOMPASSONE_TEST_PLATFORM = $currentPlatform
            $env:PSCOMPASSONE_TEST_PATHS = ConvertTo-Json $testDirs
            $env:PSCOMPASSONE_TEST_SETTINGS = ConvertTo-Json $testSettings
        }

        # Validate environment setup
        Assert-TestEnvironment -Environment $testEnvironment

        return $testEnvironment
    }
    catch {
        Write-Error "Failed to initialize test environment: $_"
        throw
    }
}

function Set-TestCredentials {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$Platform = $script:PlatformConfig.Keys[0]
    )

    try {
        # Validate platform
        if (-not $script:PlatformConfig.ContainsKey($Platform)) {
            throw "Invalid platform specified: $Platform"
        }

        # Store credentials securely
        $secureCredentials = @{
            Username = $Credential.UserName
            Password = $Credential.Password | ConvertFrom-SecureString
            Platform = $Platform
        }

        Set-Secret -Name "PSCompassOne_TestCredentials_$Platform" -SecureValue ($secureCredentials | ConvertTo-SecureString -AsPlainText -Force)
    }
    catch {
        Write-Error "Failed to set test credentials: $_"
        throw
    }
}

function Initialize-TestDirectories {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter()]
        [string]$Platform = $script:PlatformConfig.Keys[0]
    )

    try {
        # Get platform-specific settings
        $platformSettings = $script:PlatformConfig[$Platform]
        $pathSeparator = $platformSettings.PathSeparator

        # Create directory structure
        $directories = @{
            Base = $BasePath
            Output = Join-Path $BasePath "output"
            Temp = Join-Path $BasePath "temp"
            Coverage = Join-Path $BasePath "coverage"
            Logs = Join-Path $BasePath "logs"
            MockData = Join-Path $BasePath "mockdata"
        }

        # Create directories with proper permissions
        foreach ($dir in $directories.Values) {
            if (-not (Test-Path $dir)) {
                $null = New-Item -Path $dir -ItemType Directory -Force
                
                # Set appropriate permissions
                if ($Platform -ne 'Windows') {
                    chmod 700 $dir
                }
            }
        }

        # Create .gitignore for test artifacts
        $gitignore = @"
**/output/
**/temp/
**/coverage/
**/logs/
*.log
*.xml
*.json
"@
        Set-Content -Path (Join-Path $BasePath ".gitignore") -Value $gitignore

        # Register cleanup handler
        $null = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action {
            if (Test-Path $BasePath) {
                Remove-Item -Path $BasePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        return $directories
    }
    catch {
        Write-Error "Failed to initialize test directories: $_"
        throw
    }
}

function Assert-TestEnvironment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]$Environment
    )

    $requiredKeys = @('Platform', 'PowerShellVersion', 'ModulePath', 'TestPath', 'TempPath', 'Settings')
    $missingKeys = $requiredKeys | Where-Object { -not $Environment.ContainsKey($_) }
    
    if ($missingKeys) {
        throw "Test environment missing required configuration: $($missingKeys -join ', ')"
    }

    if (-not (Test-Path $Environment.ModulePath)) {
        throw "Module path does not exist: $($Environment.ModulePath)"
    }

    if (-not (Test-Path $Environment.TestPath)) {
        throw "Test path does not exist: $($Environment.TestPath)"
    }

    if ($Environment.UseMocks -and -not $Environment.MockClient) {
        throw "Mock client not initialized but UseMocks is enabled"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-TestEnvironment',
    'Set-TestCredentials',
    'Initialize-TestDirectories'
)