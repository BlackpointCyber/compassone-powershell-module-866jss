#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

using module Microsoft.PowerShell.SecretStore # Version 1.0.6

# Global test configuration
$script:ModuleRoot = "$PSScriptRoot/.."
$script:TestConfig = Get-Content -Path "$PSScriptRoot/TestConfig/test.settings.json" | ConvertFrom-Json
$script:PerformanceMetrics = [System.Collections.Concurrent.ConcurrentDictionary[string,double]]::new()

BeforeAll {
    # Initialize test environment
    $testEnv = Initialize-TestEnvironment -ModulePath $script:ModuleRoot -TestPath $PSScriptRoot -UseMocks -CrossPlatform
    $mockClient = [MockHttpClient]::new(@{
        EnableRequestLogging = $true
        ValidateResponses = $true
        SimulateLatency = $true
        LatencyMs = 100
    })

    # Import mock data
    $script:ApiResponses = Get-Content "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
    $script:AssetData = Get-Content "$PSScriptRoot/Mocks/AssetData.json" | ConvertFrom-Json
    $script:FindingData = Get-Content "$PSScriptRoot/Mocks/FindingData.json" | ConvertFrom-Json

    # Import PSCompassOne module
    Import-Module "$script:ModuleRoot/PSCompassOne.psd1" -Force
}

Describe 'Platform-Specific Integration Tests' {
    Context 'Cross-Platform File Path Handling' {
        It 'Should handle platform-specific path separators' {
            $platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
            $testPath = Join-Path $testEnv.TempPath 'test.json'
            
            # Test path handling
            $result = New-CraftAsset -JsonPath $testPath
            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $testPath
        }

        It 'Should manage credentials securely per platform' {
            # Test credential storage
            $securePassword = ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force
            $cred = New-Object PSCredential('testuser', $securePassword)
            
            Set-CraftConfiguration -Credential $cred
            $storedCred = Get-CraftConfiguration
            
            $storedCred.Username | Should -Be 'testuser'
            $storedCred.Token | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Security Integration Tests' {
    Context 'Credential Management' {
        It 'Should securely store and retrieve API tokens' {
            # Test token lifecycle
            $token = 'test-token-123'
            $secureToken = ConvertTo-SecureString $token -AsPlainText -Force
            
            Set-CraftConfiguration -Token $secureToken
            $config = Get-CraftConfiguration
            
            $config.Token | Should -Not -Be $token # Should be secure string
            [PSCredential]::new('test', $config.Token).GetNetworkCredential().Password | Should -Be $token
        }

        It 'Should handle token rotation' {
            # Test token rotation
            $oldToken = Get-CraftConfiguration
            $newToken = 'new-token-456'
            $secureNewToken = ConvertTo-SecureString $newToken -AsPlainText -Force
            
            Set-CraftConfiguration -Token $secureNewToken -Force
            $updatedConfig = Get-CraftConfiguration
            
            $updatedConfig.Token | Should -Not -Be $oldToken.Token
        }
    }
}

Describe 'Performance Integration Tests' {
    BeforeAll {
        # Configure performance thresholds
        $script:Thresholds = @{
            SingleOperation = 2000 # 2 seconds
            BatchOperation = 20    # 50 items/second
            ModuleLoad = 1000     # 1 second
        }
    }

    Context 'Command Execution Time' {
        It 'Should execute single operations within time threshold' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            $result = Get-CraftAsset -Id $AssetData.singleAsset.id
            
            $sw.Stop()
            $script:PerformanceMetrics['SingleOperation'] = $sw.ElapsedMilliseconds
            $sw.ElapsedMilliseconds | Should -BeLessThan $Thresholds.SingleOperation
        }

        It 'Should handle batch processing efficiently' {
            $itemCount = 50
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            $result = Get-CraftAssetList -PageSize $itemCount
            
            $sw.Stop()
            $timePerItem = $sw.ElapsedMilliseconds / $itemCount
            $script:PerformanceMetrics['BatchOperation'] = $timePerItem
            $timePerItem | Should -BeLessThan $Thresholds.BatchOperation
        }
    }
}

Describe 'Error Recovery Integration Tests' {
    Context 'Network Error Handling' {
        It 'Should handle connection failures gracefully' {
            # Simulate network failure
            $mockClient.ErrorSimulation.EnableRandomErrors = $true
            $mockClient.ErrorSimulation.ErrorRate = 1.0
            $mockClient.ErrorSimulation.ErrorTypes = @('503')
            
            { Get-CraftAsset -Id $AssetData.singleAsset.id -ErrorAction Stop } | 
                Should -Throw -ErrorId 'PSCompassOne.ConnectionError'
        }

        It 'Should implement retry logic for transient errors' {
            # Test retry mechanism
            $mockClient.ErrorSimulation.ErrorRate = 0.5
            $mockClient.ErrorSimulation.ErrorTypes = @('429', '503')
            
            $result = Get-CraftAsset -Id $AssetData.singleAsset.id
            $result | Should -Not -BeNullOrEmpty
            
            $retryCount = ($mockClient.RequestHistory | 
                Where-Object { $_.Uri -like "*$($AssetData.singleAsset.id)" }).Count
            $retryCount | Should -BeGreaterThan 1
        }
    }

    Context 'API Error Handling' {
        It 'Should handle rate limiting correctly' {
            # Test rate limit handling
            $mockClient.ErrorSimulation.ErrorTypes = @('429')
            $mockClient.ErrorSimulation.ErrorRate = 1.0
            
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            { Get-CraftAsset -Id $AssetData.singleAsset.id } | Should -Not -Throw
            $sw.Stop()
            
            # Verify backoff was implemented
            $sw.ElapsedMilliseconds | Should -BeGreaterThan 1000
        }

        It 'Should handle authentication failures appropriately' {
            # Test auth failure handling
            $mockClient.ErrorSimulation.ErrorTypes = @('401')
            $mockClient.ErrorSimulation.ErrorRate = 1.0
            
            { Get-CraftAsset -Id $AssetData.singleAsset.id -ErrorAction Stop } | 
                Should -Throw -ErrorId 'PSCompassOne.Unauthorized'
        }
    }
}

AfterAll {
    # Export performance metrics
    $metricsPath = Join-Path $testEnv.Directories.Output 'performance_metrics.json'
    $script:PerformanceMetrics | ConvertTo-Json | Set-Content -Path $metricsPath

    # Cleanup test environment
    if ($testEnv.UseMocks) {
        Clear-MockResponses
    }
    
    # Remove test credentials
    $null = Remove-Secret -Name 'PSCompassOne_TestCredentials' -ErrorAction SilentlyContinue
    
    # Remove temporary files
    foreach ($dir in $testEnv.Directories.Values) {
        if (Test-Path $dir) {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}