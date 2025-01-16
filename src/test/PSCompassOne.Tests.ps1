#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

using module Microsoft.PowerShell.SecretStore # Version 1.0.6

# Import test helpers and configuration
. "$PSScriptRoot/TestHelpers/Initialize-TestEnvironment.ps1"
. "$PSScriptRoot/TestConfig/pester.config.ps1"
. "$PSScriptRoot/Mocks/MockHttpClient.ps1"

# Global test configuration
$Global:ModuleRoot = "$PSScriptRoot/.."
$Global:TestConfig = Get-Content "$PSScriptRoot/TestConfig/test.settings.json" | ConvertFrom-Json
$Global:TestPlatform = if ($IsWindows) { 'Windows' } else { 'Unix' }

BeforeAll {
    # Initialize test environment
    $testEnv = Initialize-TestEnvironment -ModulePath $Global:ModuleRoot -TestPath $PSScriptRoot -UseMocks -CrossPlatform
    $Global:MockClient = $testEnv.MockClient
    $Global:TestSettings = $testEnv.Settings

    # Import module under test
    Import-Module "$Global:ModuleRoot/PSCompassOne.psd1" -Force
}

AfterAll {
    # Cleanup test environment
    if ($Global:MockClient) {
        Clear-MockResponses
    }
    Remove-Module PSCompassOne -Force -ErrorAction SilentlyContinue
}

Describe 'Module Import Tests' {
    Context 'Module Loading' {
        It 'Should import module successfully' {
            Get-Module PSCompassOne | Should -Not -BeNull
        }

        It 'Should have correct module version' {
            (Get-Module PSCompassOne).Version | Should -Be '1.0.0'
        }

        It 'Should export all required commands' {
            $commands = Get-Command -Module PSCompassOne
            $commands | Should -Not -BeNullOrEmpty
            $commands.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Platform Compatibility' {
        It 'Should handle platform-specific paths' {
            $pathSeparator = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = Join-Path $Global:ModuleRoot 'PSCompassOne.psd1'
            Test-Path $modulePath | Should -BeTrue
        }

        It 'Should validate PowerShell version compatibility' {
            $psVersion = $PSVersionTable.PSVersion
            $psVersion | Should -Not -BeNullOrEmpty
            $psVersion.Major | Should -BeGreaterOrEqual 5
        }
    }
}

Describe 'Authentication Tests' {
    BeforeAll {
        $testCred = [PSCredential]::new(
            'test@example.com',
            (ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force)
        )
    }

    Context 'Credential Management' {
        It 'Should store credentials securely in SecretStore' {
            Set-CraftConfiguration -Credential $testCred
            $storedCred = Get-CraftConfiguration
            $storedCred | Should -Not -BeNullOrEmpty
            $storedCred.Username | Should -Be $testCred.Username
        }

        It 'Should handle invalid credentials' {
            $invalidCred = [PSCredential]::new(
                'invalid@example.com',
                (ConvertTo-SecureString 'invalid' -AsPlainText -Force)
            )
            { Set-CraftConfiguration -Credential $invalidCred } | Should -Throw
        }

        It 'Should manage token expiration' {
            Mock Get-CraftConfiguration { 
                @{
                    Token = 'expired_token'
                    ExpiresAt = (Get-Date).AddHours(-1)
                }
            }
            { Get-CraftAsset -Id '12345' } | Should -Throw
        }
    }

    Context 'Security Controls' {
        It 'Should enforce TLS 1.2 or higher' {
            $securityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
            $securityProtocol | Should -Match 'Tls12|Tls13'
        }

        It 'Should mask sensitive information in errors' {
            $mockError = $Global:MockClient.GenerateErrorResponse('401')
            $mockError.error.message | Should -Not -Match $testCred.GetNetworkCredential().Password
        }
    }
}

Describe 'API Integration Tests' {
    BeforeAll {
        # Load mock responses
        $mockResponses = Get-Content "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
        $assetData = Get-Content "$PSScriptRoot/Mocks/AssetData.json" | ConvertFrom-Json
        $findingData = Get-Content "$PSScriptRoot/Mocks/FindingData.json" | ConvertFrom-Json
    }

    Context 'Request/Response Handling' {
        It 'Should make successful API calls' {
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/test-id' -Response $mockResponses.successResponses.getAssetResponse
            $result = Get-CraftAsset -Id 'test-id'
            $result | Should -Not -BeNullOrEmpty
            $result.id | Should -Be $assetData.singleAsset.id
        }

        It 'Should handle API errors correctly' {
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/invalid' -Response $mockResponses.errorResponses.notFoundResponse
            { Get-CraftAsset -Id 'invalid' } | Should -Throw
        }

        It 'Should implement retry logic' {
            $Global:MockClient.ErrorSimulation.EnableRandomErrors = $true
            $Global:MockClient.ErrorSimulation.ErrorRate = 0.5
            { Get-CraftAsset -Id 'test-id' } | Should -Not -Throw
            $Global:MockClient.ErrorSimulation.EnableRandomErrors = $false
        }

        It 'Should handle rate limiting' {
            Add-MockResponse -Method 'GET' -Uri '/v1/assets' -Response $mockResponses.errorResponses.rateLimitResponse
            { Get-CraftAssetList } | Should -Throw
            $Global:MockClient.GetRequestHistory().Count | Should -BeGreaterThan 1
        }
    }

    Context 'Response Processing' {
        It 'Should deserialize JSON responses correctly' {
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/test-id' -Response $mockResponses.successResponses.getAssetResponse
            $result = Get-CraftAsset -Id 'test-id'
            $result.PSObject.Properties | Should -Not -BeNullOrEmpty
        }

        It 'Should handle different response formats' {
            Add-MockResponse -Method 'GET' -Uri '/v1/assets' -Response $mockResponses.successResponses.getAssetListResponse
            $result = Get-CraftAssetList
            $result | Should -BeOfType [System.Object[]]
        }
    }
}

Describe 'Command Tests' {
    Context 'Asset Commands' {
        It 'Should get single asset' {
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/test-id' -Response $mockResponses.successResponses.getAssetResponse
            $result = Get-CraftAsset -Id 'test-id'
            $result | Should -Not -BeNullOrEmpty
            $result.id | Should -Be $assetData.singleAsset.id
        }

        It 'Should list assets with pagination' {
            Add-MockResponse -Method 'GET' -Uri '/v1/assets' -Response $mockResponses.successResponses.getAssetListResponse
            $result = Get-CraftAssetList -PageSize 50
            $result.Count | Should -Be $assetData.assetList.items.Count
        }

        It 'Should create new asset' {
            $newAsset = $assetData.assetVariations.minimalAsset | ConvertTo-Json
            Add-MockResponse -Method 'POST' -Uri '/v1/assets' -Response $mockResponses.successResponses.getAssetResponse
            $result = New-CraftAsset -JsonBody $newAsset
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should update existing asset' {
            $updateAsset = $assetData.assetVariations.fullAsset | ConvertTo-Json
            Add-MockResponse -Method 'PATCH' -Uri '/v1/assets/test-id' -Response $mockResponses.successResponses.getAssetResponse
            $result = Set-CraftAsset -Id 'test-id' -JsonBody $updateAsset
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should delete asset' {
            Add-MockResponse -Method 'DELETE' -Uri '/v1/assets/test-id' -Response @{ statusCode = 204 }
            { Remove-CraftAsset -Id 'test-id' } | Should -Not -Throw
        }
    }

    Context 'Finding Commands' {
        It 'Should get single finding' {
            Add-MockResponse -Method 'GET' -Uri '/v1/findings/test-id' -Response $mockResponses.successResponses.getFindingResponse
            $result = Get-CraftFinding -Id 'test-id'
            $result | Should -Not -BeNullOrEmpty
            $result.id | Should -Be $findingData.mockFindings.basicFinding.id
        }

        It 'Should list findings with filtering' {
            Add-MockResponse -Method 'GET' -Uri '/v1/findings' -Response $mockResponses.successResponses.getFindingListResponse
            $result = Get-CraftFindingList -Status 'New' -Severity 'High'
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter Validation' {
        It 'Should validate required parameters' {
            { Get-CraftAsset } | Should -Throw
            { New-CraftAsset } | Should -Throw
        }

        It 'Should validate parameter types' {
            { Get-CraftAsset -Id 123 } | Should -Throw
            { Get-CraftAssetList -PageSize 'invalid' } | Should -Throw
        }
    }
}

Describe 'Performance Tests' {
    Context 'Response Times' {
        It 'Should meet response time requirements' {
            $Global:MockClient.LatencySimulation.Enabled = $true
            $Global:MockClient.LatencySimulation.LatencyMs = 50
            
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Get-CraftAsset -Id 'test-id'
            $sw.Stop()
            
            $sw.ElapsedMilliseconds | Should -BeLessThan 2000
        }

        It 'Should handle parallel requests efficiently' {
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    Get-CraftAssetList
                }
            }
            $results = $jobs | Wait-Job | Receive-Job
            $results.Count | Should -Be 5
        }
    }

    Context 'Resource Management' {
        It 'Should implement proper caching' {
            $firstCall = Get-CraftAsset -Id 'test-id'
            $secondCall = Get-CraftAsset -Id 'test-id'
            $Global:MockClient.GetRequestHistory().Count | Should -Be 1
        }

        It 'Should handle large datasets' {
            $largeResponse = @{ items = 1..1000 | ForEach-Object { $assetData.singleAsset.Clone() } }
            Add-MockResponse -Method 'GET' -Uri '/v1/assets' -Response $largeResponse
            $result = Get-CraftAssetList -PageSize 1000
            $result.Count | Should -Be 1000
        }
    }
}