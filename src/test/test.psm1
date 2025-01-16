#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

# Import required test helper modules
. "$PSScriptRoot/TestHelpers/Initialize-TestEnvironment.ps1"
. "$PSScriptRoot/TestHelpers/Test-ApiResponse.ps1"
. "$PSScriptRoot/TestHelpers/Test-SecurityControl.ps1"

# Global test environment paths
$script:TestRoot = $PSScriptRoot
$script:ModuleRoot = "$PSScriptRoot/.."
$script:TestDataPath = "$PSScriptRoot/TestData"
$script:TestConfigPath = "$PSScriptRoot/TestConfig"
$script:PlatformConfig = "$PSScriptRoot/TestConfig/platform-specific"
$script:TestResults = "$PSScriptRoot/TestResults"

function Initialize-TestModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter()]
        [switch]$UseMocks,

        [Parameter()]
        [hashtable]$PlatformConfig,

        [Parameter()]
        [switch]$EnableParallel
    )

    try {
        # Load test configuration
        $testSettings = Get-Content -Path "$TestConfigPath/test.settings.json" | ConvertFrom-Json

        # Initialize test environment
        $testEnvironment = Initialize-TestEnvironment -ModulePath $ModulePath `
                                                    -TestPath $TestRoot `
                                                    -UseMocks:$UseMocks `
                                                    -CrossPlatform:$true

        # Configure platform-specific settings
        $platformSettings = if ($PlatformConfig) {
            $PlatformConfig
        } else {
            $testEnvironment.Platform | ForEach-Object {
                @{
                    Windows = @{ PathSeparator = '\'; TempPath = "$env:TEMP\PSCompassOne" }
                    Linux = @{ PathSeparator = '/'; TempPath = '/tmp/PSCompassOne' }
                    MacOS = @{ PathSeparator = '/'; TempPath = '/tmp/PSCompassOne' }
                }
            }
        }

        # Initialize Pester configuration
        $pesterConfig = New-PSCompassOnePesterConfig
        $pesterConfig.Run.Path = $testEnvironment.TestPath
        $pesterConfig.Run.PassThru = $true
        $pesterConfig.Run.Container.Parallel = $EnableParallel.IsPresent
        $pesterConfig.Run.Container.Jobs = $testSettings.TestExecution.MaxParallelJobs

        # Configure test coverage settings
        $pesterConfig.CodeCoverage.Enabled = $true
        $pesterConfig.CodeCoverage.Path = $ModulePath
        $pesterConfig.CodeCoverage.OutputPath = Join-Path $TestResults "coverage"
        $pesterConfig.CodeCoverage.CoveragePercentTarget = 100

        # Initialize security validation
        $securityConfig = @{
            TlsVersion = '1.2'
            EncryptionAlgorithm = 'AES-256'
            ValidateHeaders = $true
            ValidateParameters = $true
            StrictValidation = $true
        }

        # Return test configuration
        return @{
            Environment = $testEnvironment
            PesterConfig = $pesterConfig
            SecurityConfig = $securityConfig
            Settings = $testSettings
            PlatformConfig = $platformSettings
        }
    }
    catch {
        Write-Error "Failed to initialize test module: $_"
        throw
    }
}

function Invoke-ModuleTest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$TestPath,

        [Parameter(Mandatory)]
        [hashtable]$Configuration,

        [Parameter()]
        [switch]$Parallel,

        [Parameter()]
        [int]$ThrottleLimit = 4
    )

    try {
        # Validate test configuration
        if (-not $Configuration.PesterConfig) {
            throw "Invalid test configuration: Missing PesterConfig"
        }

        # Configure parallel execution
        if ($Parallel) {
            $Configuration.PesterConfig.Run.Container.Parallel = $true
            $Configuration.PesterConfig.Run.Container.Jobs = $ThrottleLimit
        }

        # Initialize test environment
        Write-Verbose "Initializing test environment..."
        $testEnv = $Configuration.Environment
        $null = Set-Location -Path $testEnv.TestPath

        # Configure test coverage
        $coveragePath = Join-Path $testEnv.Directories.Coverage "coverage.xml"
        $Configuration.PesterConfig.CodeCoverage.OutputPath = $coveragePath

        # Execute tests
        Write-Verbose "Executing tests with configuration: $($Configuration.PesterConfig | ConvertTo-Json -Depth 3)"
        $testResults = Invoke-Pester -Configuration $Configuration.PesterConfig

        # Validate test results
        if (-not $testResults) {
            throw "Test execution failed: No results returned"
        }

        # Generate test report
        $reportPath = Join-Path $testEnv.Directories.Output "TestReport.xml"
        $testResults | Export-NUnitReport -Path $reportPath

        # Validate code coverage
        $coverageThreshold = $Configuration.PesterConfig.CodeCoverage.CoveragePercentTarget
        if ($testResults.CodeCoverage.CoveragePercent -lt $coverageThreshold) {
            throw "Code coverage ($($testResults.CodeCoverage.CoveragePercent)%) below required threshold ($coverageThreshold%)"
        }

        # Return test results
        return $testResults
    }
    catch {
        Write-Error "Test execution failed: $_"
        throw
    }
    finally {
        # Cleanup test environment
        if ($testEnv -and $testEnv.Directories) {
            Write-Verbose "Cleaning up test environment..."
            Get-ChildItem -Path $testEnv.Directories.Temp -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-TestModule',
    'Invoke-ModuleTest'
)

# Export test helper functions
Export-ModuleMember -Function @(
    'Test-ApiResponseStatus',
    'Test-ApiResponseHeaders',
    'Test-ApiResponseBody',
    'Test-ApiErrorResponse',
    'Test-ApiPaginatedResponse',
    'Test-TlsProtocol',
    'Test-DataEncryption',
    'Test-InputValidation',
    'Test-SecureOutput'
)