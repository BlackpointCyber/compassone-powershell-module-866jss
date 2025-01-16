# PSake build script for PSCompassOne module testing
# Version: 1.0.0
# Requires: psake 4.9.0, Pester 5.3.0

# Import required modules
using module psake # Version 4.9.0
using module Pester # Version 5.3.0

# Import test configuration
. ./TestConfig/pester.config.ps1

# Define script-level properties
Properties {
    $TestsPath = './'
    $OutputPath = './test-results'
    $CoveragePath = './coverage'
    $ModuleName = 'PSCompassOne'
    $ModuleVersion = '1.0.0'
}

# Initialize test environment
function Initialize-TestEnvironment {
    [CmdletBinding()]
    param()

    Write-Verbose "Initializing test environment for $ModuleName v$ModuleVersion"

    # Validate PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell version 5.1 or higher is required. Current version: $($PSVersionTable.PSVersion)"
    }

    # Create output directories if they don't exist
    @($OutputPath, $CoveragePath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $_"
        }
    }

    # Load and validate configurations
    try {
        $script:testSettings = Get-Content -Path "$TestsPath/TestConfig/test.settings.json" -Raw | ConvertFrom-Json
        $script:coverageSettings = Get-Content -Path "$TestsPath/coverage.settings.json" -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to load test configuration files: $_"
    }

    # Initialize Pester configuration
    $script:pesterConfig = New-PSCompassOnePesterConfig

    # Set platform-specific variables
    $script:isWindows = $PSVersionTable.Platform -eq 'Win32NT'
    $script:isCore = $PSVersionTable.PSEdition -eq 'Core'

    # Verify required modules
    @('Pester', 'psake') | ForEach-Object {
        if (-not (Get-Module -ListAvailable -Name $_)) {
            throw "Required module not found: $_"
        }
    }

    Write-Verbose "Test environment initialization completed"
}

# Execute module tests
function Invoke-ModuleTest {
    [CmdletBinding()]
    param(
        [string]$TestPath = $TestsPath,
        [string[]]$Tags = @()
    )

    Write-Verbose "Executing tests for $ModuleName"

    try {
        # Configure test execution
        $testConfig = $script:pesterConfig
        if ($Tags.Count -gt 0) {
            $testConfig.Filter.Tag = $Tags
        }

        # Set platform-specific isolation
        if ($script:isCore) {
            $testConfig.Run.EnableRunAsAdministrator = $false
            $testConfig.Run.UseSeparateProcesses = $true
        }

        # Execute tests
        $testResults = Invoke-Pester -Configuration $testConfig

        # Process results
        if ($testResults.FailedCount -gt 0) {
            throw "Tests failed: $($testResults.FailedCount) failures"
        }

        # Generate coverage reports
        if ($testResults.CodeCoverage) {
            $coverageReport = @{
                Path = Join-Path $CoveragePath "coverage.xml"
                Format = $testConfig.CodeCoverage.OutputFormat
                ThresholdFailed = $false
            }

            # Validate coverage thresholds
            $coverage = $testResults.CodeCoverage.CoveragePercent
            if ($coverage -lt $script:coverageSettings.CoverageThresholds.Minimum) {
                $coverageReport.ThresholdFailed = $true
                Write-Warning "Code coverage below minimum threshold: $coverage% < $($script:coverageSettings.CoverageThresholds.Minimum)%"
            }

            # Export coverage report
            $testResults.CodeCoverage | Export-CodeCoverageReport @coverageReport
        }

        return $testResults
    }
    catch {
        Write-Error "Test execution failed: $_"
        throw
    }
}

# Default task - runs all tests
Task default -Depends Test

# Initialize test environment
Task Init {
    Write-Verbose "Initializing build environment"
    Initialize-TestEnvironment
}

# Run all tests
Task Test -Depends Init {
    Write-Verbose "Executing test suite"

    try {
        # Load test configuration
        $testConfig = $script:testSettings.TestExecution

        # Configure parallel execution
        $parallelParams = @{
            ThrottleLimit = $testConfig.ParallelJobs
            TimeoutSeconds = $testConfig.TestTimeout
        }

        # Execute tests across platforms
        $testResults = Invoke-ModuleTest -Tags $testConfig.TestCategories

        # Export test results
        $testResults | Export-CliXml -Path (Join-Path $OutputPath "testResults.xml")

        # Generate test summary
        $summary = @{
            TotalCount = $testResults.TotalCount
            PassedCount = $testResults.PassedCount
            FailedCount = $testResults.FailedCount
            SkippedCount = $testResults.SkippedCount
            Duration = $testResults.Duration
        }

        $summary | ConvertTo-Json | Set-Content -Path (Join-Path $OutputPath "summary.json")

        if ($testResults.FailedCount -gt 0) {
            throw "Test execution failed with $($testResults.FailedCount) failures"
        }
    }
    catch {
        Write-Error "Test task failed: $_"
        throw
    }
}

# Generate code coverage reports
Task Coverage -Depends Test {
    Write-Verbose "Generating code coverage reports"

    try {
        # Process coverage data
        $coverageData = Import-CliXml -Path (Join-Path $CoveragePath "coverage.xml")

        # Generate HTML report
        $htmlParams = @{
            Path = Join-Path $CoveragePath "coverage.html"
            Format = 'HTML'
            Title = "$ModuleName Code Coverage Report"
        }
        $coverageData | Export-CodeCoverageReport @htmlParams

        # Validate coverage thresholds
        $thresholds = $script:coverageSettings.CoverageThresholds
        if ($coverageData.CoveragePercent -lt $thresholds.Minimum) {
            throw "Code coverage below minimum threshold: $($coverageData.CoveragePercent)% < $($thresholds.Minimum)%"
        }

        # Generate coverage badge
        $badgeColor = switch ($coverageData.CoveragePercent) {
            {$_ -ge 90} { 'brightgreen' }
            {$_ -ge 75} { 'yellow' }
            default { 'red' }
        }

        $badgeJson = @{
            schemaVersion = 1
            label = 'coverage'
            message = "$($coverageData.CoveragePercent)%"
            color = $badgeColor
        } | ConvertTo-Json

        $badgeJson | Set-Content -Path (Join-Path $CoveragePath "coverage-badge.json")
    }
    catch {
        Write-Error "Coverage task failed: $_"
        throw
    }
}