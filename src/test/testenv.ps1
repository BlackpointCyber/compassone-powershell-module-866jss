#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

# Global paths
$script:TestRoot = $PSScriptRoot
$script:ModuleRoot = "$PSScriptRoot/../PSCompassOne"
$script:TestConfigPath = "$PSScriptRoot/TestConfig"
$script:TestDataPath = "$PSScriptRoot/TestData"
$script:TestResultsPath = "$PSScriptRoot/test-results"
$script:TestPlatformPath = "$PSScriptRoot/TestConfig/Platforms"
$script:TestCredentialPath = "$PSScriptRoot/TestConfig/Credentials"

function Initialize-TestSession {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$UseMocks,

        [Parameter()]
        [switch]$SkipCleanup,

        [Parameter()]
        [string]$Platform = $(if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }),

        [Parameter()]
        [hashtable]$CredentialConfig,

        [Parameter()]
        [string]$TestScope = 'All'
    )

    try {
        # Load test settings
        $testSettings = Get-Content -Path "$TestConfigPath/test.settings.json" -Raw | ConvertFrom-Json

        # Initialize test environment
        $testEnvironment = Initialize-TestEnvironment -ModulePath $ModuleRoot -TestPath $TestRoot -UseMocks:$UseMocks.IsPresent -CrossPlatform:($TestScope -eq 'CrossPlatform')

        # Configure Pester
        $pesterConfig = New-PSCompassOnePesterConfig
        $pesterConfig.Run.Path = $TestRoot
        $pesterConfig.TestResult.OutputPath = Join-Path $TestResultsPath "results_$Platform.xml"
        $pesterConfig.CodeCoverage.OutputPath = Join-Path $TestResultsPath "coverage_$Platform.xml"

        # Set up mock data if requested
        if ($UseMocks) {
            # Load mock data
            $mockData = @{
                Assets = Get-Content "$TestRoot/Mocks/AssetData.json" | ConvertFrom-Json
                Findings = Get-Content "$TestRoot/Mocks/FindingData.json" | ConvertFrom-Json
                ApiResponses = Get-Content "$TestRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
            }

            # Initialize mock client
            $mockClient = New-MockHttpClient -Configuration @{
                EnableRequestLogging = $true
                ValidateResponses = $true
                SimulateLatency = $testSettings.TestEnvironment.MockResponses
            }

            # Add mock responses
            foreach ($response in $mockData.ApiResponses.successResponses.PSObject.Properties) {
                Add-MockResponse -Method 'GET' -Uri "*/$($response.Name)*" -Response $response.Value
            }
        }

        # Configure credentials
        if ($CredentialConfig) {
            $secureCredentials = @{
                ApiKey = ConvertTo-SecureString $CredentialConfig.ApiKey -AsPlainText -Force
                ApiUrl = $testSettings.TestEnvironment.ApiEndpoint
            }
            Set-Secret -Name "PSCompassOne_Test_$Platform" -SecureValue ($secureCredentials | ConvertTo-SecureString -AsPlainText -Force)
        }

        # Set up test session configuration
        $testSession = @{
            Platform = $Platform
            PowerShellVersion = $PSVersionTable.PSVersion
            TestScope = $TestScope
            UseMocks = $UseMocks.IsPresent
            SkipCleanup = $SkipCleanup.IsPresent
            Paths = @{
                ModuleRoot = $ModuleRoot
                TestRoot = $TestRoot
                TestConfig = $TestConfigPath
                TestData = $TestDataPath
                TestResults = $TestResultsPath
                Platform = $TestPlatformPath
            }
            Settings = $testSettings
            PesterConfig = $pesterConfig
            MockData = if ($UseMocks) { $mockData } else { $null }
            MockClient = if ($UseMocks) { $mockClient } else { $null }
        }

        # Set environment variables
        $env:PSCOMPASSONE_TEST_SESSION = ConvertTo-Json $testSession -Depth 10
        $env:PSCOMPASSONE_TEST_PLATFORM = $Platform
        $env:PSCOMPASSONE_TEST_MODE = if ($UseMocks) { 'Mock' } else { 'Live' }

        return $testSession
    }
    catch {
        Write-Error "Failed to initialize test session: $_"
        throw
    }
}

function Reset-TestSession {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [string]$Platform = $env:PSCOMPASSONE_TEST_PLATFORM,

        [Parameter()]
        [switch]$PreserveCredentials
    )

    try {
        # Load current session
        $testSession = $env:PSCOMPASSONE_TEST_SESSION | ConvertFrom-Json

        if (-not $testSession -and -not $Force) {
            throw "No active test session found. Use -Force to cleanup anyway."
        }

        # Clean up test results
        if (Test-Path $TestResultsPath) {
            Remove-Item -Path $TestResultsPath -Recurse -Force
        }

        # Remove mock data
        if ($testSession.UseMocks) {
            Clear-MockResponses
        }

        # Clean up credentials unless preserved
        if (-not $PreserveCredentials) {
            Remove-Secret -Name "PSCompassOne_Test_$Platform" -ErrorAction SilentlyContinue
        }

        # Clean up environment variables
        Remove-Item Env:\PSCOMPASSONE_TEST_SESSION -ErrorAction SilentlyContinue
        Remove-Item Env:\PSCOMPASSONE_TEST_PLATFORM -ErrorAction SilentlyContinue
        Remove-Item Env:\PSCOMPASSONE_TEST_MODE -ErrorAction SilentlyContinue

        # Clean up temporary files
        $tempPath = if ($Platform -eq 'Windows') { 
            "$env:TEMP\PSCompassOne" 
        } else { 
            "/tmp/PSCompassOne" 
        }
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force
        }
    }
    catch {
        Write-Error "Failed to reset test session: $_"
        if ($Force) {
            Write-Warning "Continuing cleanup despite errors due to -Force"
        }
        else {
            throw
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-TestSession',
    'Reset-TestSession'
)