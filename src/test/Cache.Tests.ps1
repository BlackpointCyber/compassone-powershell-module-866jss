using module Microsoft.PowerShell.Utility # Version 5.1.0+
using module Pester # Version 5.3.0+

BeforeAll {
    # Import required test configuration and mocks
    . "$PSScriptRoot/TestConfig/pester.config.ps1"
    . "$PSScriptRoot/Mocks/MockHttpClient.ps1"
    . "$PSScriptRoot/TestHelpers/Test-ApiResponse.ps1"

    # Initialize test configuration
    $script:TestConfig = New-PSCompassOnePesterConfig
    $script:MockClient = New-MockHttpClient
    
    # Load test data
    $script:MockData = @{
        Assets = Get-Content -Path "$PSScriptRoot/Mocks/AssetData.json" | ConvertFrom-Json
        Findings = Get-Content -Path "$PSScriptRoot/Mocks/FindingData.json" | ConvertFrom-Json
    }

    # Cache test settings
    $script:CacheTestSettings = @{
        DefaultTTL = 300 # 5 minutes
        MaxCacheSize = 1000
        PerformanceThresholds = @{
            MaxRetrievalTime = 2 # seconds
            MinBatchOpsPerSecond = 50
        }
        ConcurrentOperations = 100
    }
}

Describe 'Cache Operations' {
    BeforeEach {
        # Initialize clean cache state for each test
        Initialize-TestCache
    }

    Context 'Cache Storage' {
        It 'Should store API response in cache with correct key format' {
            # Arrange
            $assetId = $script:MockData.Assets.singleAsset.id
            $response = $script:MockData.Assets.singleAsset
            $cacheKey = "Asset:$assetId"

            # Act
            Set-CacheEntry -Key $cacheKey -Value $response
            $cachedValue = Get-CacheEntry -Key $cacheKey

            # Assert
            $cachedValue | Should -Not -BeNullOrEmpty
            $cachedValue.id | Should -Be $assetId
            Test-ApiResponseBody -Response @{ body = $cachedValue } -ExpectedTemplate $response | Should -BeTrue
        }

        It 'Should retrieve cached response with data integrity' {
            # Arrange
            $finding = $script:MockData.Findings.mockFindings.basicFinding
            $cacheKey = "Finding:$($finding.id)"

            # Act
            Set-CacheEntry -Key $cacheKey -Value $finding
            $cachedValue = Get-CacheEntry -Key $cacheKey

            # Assert
            $cachedValue | Should -Not -BeNullOrEmpty
            Compare-Object $finding $cachedValue -Property id, findingClass, name, severity, status | Should -BeNullOrEmpty
        }

        It 'Should return null for non-existent cache keys' {
            # Act
            $result = Get-CacheEntry -Key "NonExistent:12345"

            # Assert
            $result | Should -BeNullOrEmpty
        }

        It 'Should handle concurrent cache access safely' {
            # Arrange
            $assets = $script:MockData.Assets.assetList.items
            $jobs = @()

            # Act
            foreach ($asset in $assets) {
                $jobs += Start-Job -ScriptBlock {
                    param($asset)
                    Set-CacheEntry -Key "Asset:$($asset.id)" -Value $asset
                } -ArgumentList $asset
            }

            Wait-Job -Job $jobs | Out-Null
            Receive-Job -Job $jobs | Out-Null

            # Assert
            foreach ($asset in $assets) {
                $cachedValue = Get-CacheEntry -Key "Asset:$($asset.id)"
                $cachedValue | Should -Not -BeNullOrEmpty
                $cachedValue.id | Should -Be $asset.id
            }
        }

        It 'Should maintain cache size within configured limits' {
            # Arrange
            $maxSize = $script:CacheTestSettings.MaxCacheSize
            $items = 1..$maxSize | ForEach-Object {
                @{
                    id = "test-$_"
                    value = "test-value-$_"
                }
            }

            # Act
            foreach ($item in $items) {
                Set-CacheEntry -Key "Test:$($item.id)" -Value $item
            }

            # Add one more to trigger eviction
            Set-CacheEntry -Key "Test:overflow" -Value @{ id = "overflow" }

            # Assert
            $cacheSize = Get-CacheSize
            $cacheSize | Should -BeLessOrEqual $maxSize
        }
    }

    Context 'Cache Expiration' {
        It 'Should expire cache entries after configured TTL' {
            # Arrange
            $asset = $script:MockData.Assets.singleAsset
            $cacheKey = "Asset:$($asset.id)"
            Set-CacheEntry -Key $cacheKey -Value $asset -TTL 1

            # Act
            Start-Sleep -Seconds 2
            $cachedValue = Get-CacheEntry -Key $cacheKey

            # Assert
            $cachedValue | Should -BeNullOrEmpty
        }

        It 'Should refresh TTL on cache access' {
            # Arrange
            $finding = $script:MockData.Findings.mockFindings.basicFinding
            $cacheKey = "Finding:$($finding.id)"
            Set-CacheEntry -Key $cacheKey -Value $finding -TTL 2

            # Act
            Start-Sleep -Seconds 1
            $firstAccess = Get-CacheEntry -Key $cacheKey -RefreshTTL
            Start-Sleep -Seconds 1
            $secondAccess = Get-CacheEntry -Key $cacheKey

            # Assert
            $firstAccess | Should -Not -BeNullOrEmpty
            $secondAccess | Should -Not -BeNullOrEmpty
        }

        It 'Should cleanup expired entries automatically' {
            # Arrange
            1..5 | ForEach-Object {
                Set-CacheEntry -Key "Test:$_" -Value "Value$_" -TTL 1
            }

            # Act
            Start-Sleep -Seconds 2
            Invoke-CacheCleanup

            # Assert
            $cacheSize = Get-CacheSize
            $cacheSize | Should -Be 0
        }
    }

    Context 'Cache Validation' {
        It 'Should validate cache key format strictly' {
            # Arrange
            $invalidKeys = @(
                "",
                $null,
                "Invalid Key",
                "Asset:",
                ":12345"
            )

            # Act & Assert
            foreach ($key in $invalidKeys) {
                { Set-CacheEntry -Key $key -Value "test" } | Should -Throw
            }
        }

        It 'Should ensure cached data integrity' {
            # Arrange
            $asset = $script:MockData.Assets.singleAsset
            $cacheKey = "Asset:$($asset.id)"

            # Act
            Set-CacheEntry -Key $cacheKey -Value $asset
            $cachedValue = Get-CacheEntry -Key $cacheKey

            # Assert
            $cachedValue | Should -Not -BeNullOrEmpty
            $cachedValue.GetType() | Should -Be $asset.GetType()
            $cachedValue.PSObject.Properties.Name | Should -Be $asset.PSObject.Properties.Name
        }
    }

    Context 'Cache Performance' {
        It 'Should retrieve cached data within 2s threshold' {
            # Arrange
            $asset = $script:MockData.Assets.singleAsset
            $cacheKey = "Asset:$($asset.id)"
            Set-CacheEntry -Key $cacheKey -Value $asset

            # Act
            $timer = Measure-Command {
                1..1000 | ForEach-Object {
                    $null = Get-CacheEntry -Key $cacheKey
                }
            }

            # Assert
            $timer.TotalSeconds | Should -BeLessThan $script:CacheTestSettings.PerformanceThresholds.MaxRetrievalTime
        }

        It 'Should handle 50+ concurrent cache operations per second' {
            # Arrange
            $operations = 1..$script:CacheTestSettings.ConcurrentOperations
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $jobs = @()

            # Act
            foreach ($op in $operations) {
                $jobs += Start-Job -ScriptBlock {
                    param($id)
                    Set-CacheEntry -Key "Test:$id" -Value "Value$id"
                    Get-CacheEntry -Key "Test:$id"
                } -ArgumentList $op
            }

            Wait-Job -Job $jobs | Out-Null
            $timer.Stop()

            # Assert
            $opsPerSecond = $operations / $timer.Elapsed.TotalSeconds
            $opsPerSecond | Should -BeGreaterThan $script:CacheTestSettings.PerformanceThresholds.MinBatchOpsPerSecond
        }
    }

    Context 'Thread Safety' {
        It 'Should handle parallel cache access without corruption' {
            # Arrange
            $assets = $script:MockData.Assets.assetList.items
            $jobs = @()

            # Act - Parallel writes and reads
            foreach ($asset in $assets) {
                $jobs += Start-Job -ScriptBlock {
                    param($asset)
                    Set-CacheEntry -Key "Asset:$($asset.id)" -Value $asset
                    Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 100)
                    Get-CacheEntry -Key "Asset:$($asset.id)"
                } -ArgumentList $asset
            }

            $results = Wait-Job -Job $jobs | Receive-Job

            # Assert
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be $assets.Count
            foreach ($result in $results) {
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should maintain data consistency during concurrent operations' {
            # Arrange
            $finding = $script:MockData.Findings.mockFindings.basicFinding
            $cacheKey = "Finding:$($finding.id)"
            $jobs = @()

            # Act - Multiple concurrent updates
            1..10 | ForEach-Object {
                $jobs += Start-Job -ScriptBlock {
                    param($finding, $iteration)
                    $finding.status = "Status$iteration"
                    Set-CacheEntry -Key "Finding:$($finding.id)" -Value $finding
                    Get-CacheEntry -Key "Finding:$($finding.id)"
                } -ArgumentList $finding, $_
            }

            $results = Wait-Job -Job $jobs | Receive-Job

            # Assert
            $results | Should -Not -BeNullOrEmpty
            $lastResult = Get-CacheEntry -Key $cacheKey
            $lastResult | Should -Not -BeNullOrEmpty
            $lastResult.status | Should -BeLike "Status*"
        }
    }
}

# Helper Functions
function Initialize-TestCache {
    # Clear existing cache
    Clear-Cache

    # Configure cache settings
    Set-CacheConfiguration -TTL $script:CacheTestSettings.DefaultTTL -MaxSize $script:CacheTestSettings.MaxCacheSize

    # Reset mock client
    $script:MockClient = New-MockHttpClient
}

function Test-CachePerformance {
    param(
        [string]$Operation,
        [int]$Iterations
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $memoryBefore = [System.GC]::GetTotalMemory($true)

    switch ($Operation) {
        'Get' {
            1..$Iterations | ForEach-Object {
                $null = Get-CacheEntry -Key "Test:$_"
            }
        }
        'Set' {
            1..$Iterations | ForEach-Object {
                Set-CacheEntry -Key "Test:$_" -Value "Value$_"
            }
        }
    }

    $timer.Stop()
    $memoryAfter = [System.GC]::GetTotalMemory($true)

    return @{
        Operation = $Operation
        Iterations = $Iterations
        Duration = $timer.Elapsed
        OperationsPerSecond = $Iterations / $timer.Elapsed.TotalSeconds
        MemoryUsage = $memoryAfter - $memoryBefore
    }
}