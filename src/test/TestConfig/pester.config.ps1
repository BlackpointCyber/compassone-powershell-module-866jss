# Pester 5.3.0 Configuration File for PSCompassOne Module Testing
# Implements comprehensive test configuration with cross-platform support,
# parallel execution, and 100% code coverage requirements

function New-PSCompassOnePesterConfig {
    [CmdletBinding()]
    [OutputType([PesterConfiguration])]
    param()

    # Initialize new PesterConfiguration object
    $config = [PesterConfiguration]::new()

    #region Run Configuration
    $config.Run.Exit = $true
    $config.Run.Throw = $true
    $config.Run.PassThru = $true
    $config.Run.Path = @('./')
    $config.Run.ExcludePath = @(
        '**/Mocks/**',
        '**/TestData/**'
    )
    $config.Run.TestExtension = '.Tests.ps1'
    
    # Configure parallel execution
    $config.Run.Container = @{
        Parallel = $true
        Jobs = 4  # Configurable based on available cores
        MaxQueue = 10
        SkipRemainingOnFailure = $false
    }
    #endregion

    #region Filter Configuration
    $config.Filter.Tag = @(
        'Unit',
        'Integration',
        'Security',
        'Performance'
    )
    $config.Filter.ExcludeTag = @('Skip')
    $config.Filter.Line = $null
    $config.Filter.FullName = $null
    #endregion

    #region Code Coverage Configuration
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = './coverage'
    $config.CodeCoverage.OutputEncoding = 'UTF8'
    $config.CodeCoverage.Path = @(
        '*.ps1',
        '*.psm1'
    )
    $config.CodeCoverage.ExcludeTests = $true
    $config.CodeCoverage.RecursePaths = $true
    
    # Enforce 100% code coverage requirement
    $config.CodeCoverage.MinimumThreshold = 100
    $config.CodeCoverage.CoveragePercentTarget = 100
    #endregion

    #region Test Results Configuration
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = './test-results/results.xml'
    $config.TestResult.OutputEncoding = 'UTF8'
    $config.TestResult.TestSuiteName = 'PSCompassOne'
    #endregion

    #region Should Configuration
    $config.Should.ErrorAction = 'Stop'
    #endregion

    #region Debug Configuration
    $config.Debug.ShowNavigationMarkers = $false
    $config.Debug.WriteDebugMessages = $false
    $config.Debug.WriteDebugMessagesFrom = @(
        'Discovery',
        'Skip',
        'Mock',
        'CodeCoverage'
    )
    #endregion

    #region Output Configuration
    $config.Output.Verbosity = 'Detailed'
    $config.Output.CIFormat = 'Auto'
    $config.Output.StackTraceVerbosity = 'FirstLine'
    #endregion

    # Load environment-specific settings
    $testSettings = Get-Content -Path './test.settings.json' -Raw | ConvertFrom-Json
    $coverageSettings = Get-Content -Path '../coverage.settings.json' -Raw | ConvertFrom-Json
    $testMatrix = Get-Content -Path './testmatrix.json' -Raw | ConvertFrom-Json

    # Apply environment-specific configurations
    if ($testSettings.TestExecution) {
        $config.Run.Jobs = $testSettings.TestExecution.ParallelJobs
        $config.Run.MaxQueue = $testSettings.TestExecution.MaxQueueSize
    }

    # Apply coverage thresholds
    if ($coverageSettings.CoverageThresholds) {
        $config.CodeCoverage.MinimumThreshold = $coverageSettings.CoverageThresholds.Minimum
        $config.CodeCoverage.CoveragePercentTarget = $coverageSettings.CoverageThresholds.Target
    }

    # Configure platform-specific test matrix
    if ($testMatrix.powershell -and $testMatrix.operatingSystem) {
        $config.Filter.Tag += $testMatrix.testCategories
    }

    # Validate configuration
    $configurationErrors = $config.Validate()
    if ($configurationErrors.Count -gt 0) {
        throw "Invalid Pester configuration: $($configurationErrors -join '; ')"
    }

    return $config
}

# Export the configuration function
Export-ModuleMember -Function New-PSCompassOnePesterConfig