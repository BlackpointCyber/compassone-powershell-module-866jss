#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

BeforeAll {
    # Import test environment setup and configuration
    . "$PSScriptRoot/TestHelpers/Initialize-TestEnvironment.ps1"
    $testEnvironment = Initialize-TestEnvironment -ModulePath "$PSScriptRoot/../PSCompassOne" -TestPath $PSScriptRoot
    
    # Load test settings and credentials
    $testSettings = Get-Content -Path "$PSScriptRoot/TestConfig/test.settings.json" | ConvertFrom-Json
    $testCredentials = Get-Content -Path "$PSScriptRoot/Mocks/TestCredentials.json" | ConvertFrom-Json
}

Describe 'Configuration Management Tests' {
    Context 'SecretStore Integration' {
        BeforeEach {
            # Initialize clean SecretStore for each test
            $null = Initialize-SecretStore -Scope CurrentUser -Password (ConvertTo-SecureString -String "TestPassword123!" -AsPlainText -Force)
        }

        It 'Should initialize SecretStore successfully' {
            # Test SecretStore initialization
            $result = Test-SecretVault -Name 'PSCompassOneTest'
            $result | Should -BeTrue
        }

        It 'Should store credentials securely' {
            # Test credential storage
            $apiKey = $testCredentials.validCredentials.apiKey
            $apiUrl = $testCredentials.validCredentials.apiUrl
            
            Set-CraftConfiguration -ApiKey $apiKey -ApiUrl $apiUrl
            
            $storedCredentials = Get-Secret -Name 'PSCompassOne_Credentials' -AsPlainText
            $storedCredentials | Should -Not -BeNullOrEmpty
            $storedCredentials.ApiKey | Should -Be $apiKey
            $storedCredentials.ApiUrl | Should -Be $apiUrl
        }

        It 'Should retrieve credentials correctly' {
            # Test credential retrieval
            $apiKey = $testCredentials.validCredentials.apiKey
            $apiUrl = $testCredentials.validCredentials.apiUrl
            
            Set-CraftConfiguration -ApiKey $apiKey -ApiUrl $apiUrl
            $config = Get-CraftConfiguration
            
            $config.ApiKey | Should -Be $apiKey
            $config.ApiUrl | Should -Be $apiUrl
        }

        It 'Should handle credential updates' {
            # Test credential updates
            $initialKey = $testCredentials.validCredentials.apiKey
            $updatedKey = 'updated-test-api-key-67890-xyz'
            
            Set-CraftConfiguration -ApiKey $initialKey
            Set-CraftConfiguration -ApiKey $updatedKey
            
            $config = Get-CraftConfiguration
            $config.ApiKey | Should -Be $updatedKey
        }

        It 'Should securely delete credentials' {
            # Test credential deletion
            Set-CraftConfiguration -ApiKey $testCredentials.validCredentials.apiKey
            Remove-CraftConfiguration
            
            $storedCredentials = Get-Secret -Name 'PSCompassOne_Credentials' -ErrorAction SilentlyContinue
            $storedCredentials | Should -BeNullOrEmpty
        }
    }

    Context 'Environment Configuration' {
        BeforeEach {
            # Clear environment variables
            $env:PSCOMPASSONE_API_KEY = $null
            $env:PSCOMPASSONE_API_URL = $null
        }

        It 'Should handle environment variables correctly' {
            # Test environment variable configuration
            $env:PSCOMPASSONE_API_KEY = $testCredentials.validCredentials.apiKey
            $env:PSCOMPASSONE_API_URL = $testCredentials.validCredentials.apiUrl
            
            $config = Get-CraftConfiguration -UseEnvironmentVariables
            
            $config.ApiKey | Should -Be $env:PSCOMPASSONE_API_KEY
            $config.ApiUrl | Should -Be $env:PSCOMPASSONE_API_URL
        }

        It 'Should persist configuration across sessions' {
            # Test configuration persistence
            $apiKey = $testCredentials.validCredentials.apiKey
            Set-CraftConfiguration -ApiKey $apiKey -Persist
            
            # Simulate new session
            Remove-Module PSCompassOne -ErrorAction SilentlyContinue
            Import-Module "$testEnvironment.ModulePath/PSCompassOne.psd1"
            
            $config = Get-CraftConfiguration
            $config.ApiKey | Should -Be $apiKey
        }

        It 'Should validate configuration settings' {
            # Test configuration validation
            $invalidUrl = 'not-a-url'
            { Set-CraftConfiguration -ApiUrl $invalidUrl } | Should -Throw
            
            $invalidKey = '123'
            { Set-CraftConfiguration -ApiKey $invalidKey } | Should -Throw
        }
    }

    Context 'Cross-Platform Configuration' {
        BeforeAll {
            $platformConfig = @{
                Windows = @{ PathSeparator = '\'; ConfigPath = "$env:LOCALAPPDATA\PSCompassOne" }
                Linux = @{ PathSeparator = '/'; ConfigPath = "$env:HOME/.config/PSCompassOne" }
                MacOS = @{ PathSeparator = '/'; ConfigPath = "$env:HOME/Library/Preferences/PSCompassOne" }
            }
        }

        It 'Should handle platform-specific paths correctly' {
            # Test platform-specific path handling
            $platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
            $expectedPath = $platformConfig[$platform].ConfigPath
            
            $config = Get-CraftConfiguration
            $config.ConfigPath | Should -Be $expectedPath
        }

        It 'Should manage permissions correctly across platforms' {
            # Test permission handling
            $configPath = $platformConfig[$platform].ConfigPath
            
            if (-not $IsWindows) {
                $permissions = (Get-Item $configPath).Mode
                $permissions | Should -Match '^d.*700$'
            }
        }
    }

    AfterAll {
        # Cleanup test environment
        Remove-CraftConfiguration -Force
        Remove-Item -Path $testEnvironment.TempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}