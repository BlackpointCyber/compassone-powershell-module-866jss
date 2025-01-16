#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

# Import test helpers and mock data
. "$PSScriptRoot/TestHelpers/Test-Authentication.ps1"
. "$PSScriptRoot/TestHelpers/Initialize-TestEnvironment.ps1"
$mockCredentials = Get-Content "$PSScriptRoot/Mocks/TestCredentials.json" | ConvertFrom-Json

# Global test configuration
$script:TEST_API_URL = 'https://api.test.compassone.com'
$script:TEST_VAULT_NAME = 'PSCompassOneTest'
$script:TEST_TIMEOUT_SECONDS = 30
$script:TEST_RETRY_COUNT = 3
$script:TEST_PLATFORMS = @('Windows', 'Linux', 'MacOS')
$script:TEST_PERFORMANCE_THRESHOLD_MS = 2000

BeforeAll {
    # Initialize test environment
    $testEnv = Initialize-TestEnvironment -ModulePath "$PSScriptRoot/../PSCompassOne" `
                                        -TestPath $PSScriptRoot `
                                        -UseMocks `
                                        -CrossPlatform

    # Configure SecretStore
    $null = Initialize-SecretStore -Scope CurrentUser -Password (
        ConvertTo-SecureString -String "TestPassword123!" -AsPlainText -Force
    )

    # Set up test credentials
    $script:validCred = [PSCredential]::new(
        'validUser',
        (ConvertTo-SecureString -String $mockCredentials.validCredentials.apiKey -AsPlainText -Force)
    )
    $script:invalidCred = [PSCredential]::new(
        'invalidUser',
        (ConvertTo-SecureString -String $mockCredentials.invalidCredentials.apiKey -AsPlainText -Force)
    )
    $script:expiredCred = [PSCredential]::new(
        'expiredUser',
        (ConvertTo-SecureString -String $mockCredentials.expiredCredentials.apiKey -AsPlainText -Force)
    )
}

AfterAll {
    # Clean up test environment
    Remove-Secret -Name "PSCompassOne_Token" -Vault $script:TEST_VAULT_NAME -ErrorAction SilentlyContinue
    Remove-Secret -Name "PSCompassOne_Credentials_*" -Vault $script:TEST_VAULT_NAME -ErrorAction SilentlyContinue

    # Archive test logs
    $logPath = Join-Path $testEnv.Directories.Logs "authentication_tests_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Get-Content $script:SECURITY_LOG_PATH | Out-File $logPath -Encoding UTF8
}

Describe 'Authentication Tests' {
    Context 'Valid Authentication' {
        It 'Should successfully authenticate with valid credentials across platforms' {
            foreach ($platform in $script:TEST_PLATFORMS) {
                $result = Test-ValidAuthentication -Credential $script:validCred `
                                                -ApiUrl $script:TEST_API_URL `
                                                -TimeoutSeconds $script:TEST_TIMEOUT_SECONDS
                $result | Should -BeTrue
            }
        }

        It 'Should store token securely in SecretStore with encryption validation' {
            $result = Test-SecretStoreIntegration -Credential $script:validCred `
                                                -VaultName $script:TEST_VAULT_NAME
            $result | Should -BeTrue
        }

        It 'Should reuse cached token with performance monitoring' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-ValidAuthentication -Credential $script:validCred `
                                            -ApiUrl $script:TEST_API_URL
            $sw.Stop()
            $result | Should -BeTrue
            $sw.ElapsedMilliseconds | Should -BeLessThan $script:TEST_PERFORMANCE_THRESHOLD_MS
        }

        It 'Should handle token refresh with audit logging' {
            $result = Test-ExpiredAuthentication -Credential $script:validCred `
                                              -ApiUrl $script:TEST_API_URL `
                                              -ExpirationSeconds 1
            $result | Should -BeTrue
        }

        It 'Should validate token integrity' {
            $token = Get-Secret -Name "PSCompassOne_Token" -Vault $script:TEST_VAULT_NAME
            $token | Should -Not -BeNullOrEmpty
            $tokenString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
            )
            $tokenString | Should -Match $mockCredentials.validCredentials.validationPattern
        }

        It 'Should meet performance thresholds' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            1..5 | ForEach-Object {
                $result = Test-ValidAuthentication -Credential $script:validCred `
                                                -ApiUrl $script:TEST_API_URL
                $result | Should -BeTrue
            }
            $sw.Stop()
            $averageMs = $sw.ElapsedMilliseconds / 5
            $averageMs | Should -BeLessThan $script:TEST_PERFORMANCE_THRESHOLD_MS
        }
    }

    Context 'Invalid Authentication' {
        It 'Should fail authentication with detailed error validation' {
            $result = Test-InvalidAuthentication -Credential $script:invalidCred `
                                              -ApiUrl $script:TEST_API_URL
            $result | Should -BeTrue
        }

        It 'Should return platform-specific error messages' {
            foreach ($platform in $script:TEST_PLATFORMS) {
                $result = Test-InvalidAuthentication -Credential $script:invalidCred `
                                                  -ApiUrl $script:TEST_API_URL `
                                                  -ExpectedErrorTypes @("Invalid credentials")
                $result | Should -BeTrue
            }
        }

        It 'Should prevent token storage after failure' {
            Test-InvalidAuthentication -Credential $script:invalidCred -ApiUrl $script:TEST_API_URL
            $token = Get-Secret -Name "PSCompassOne_Token" -Vault $script:TEST_VAULT_NAME -ErrorAction SilentlyContinue
            $token | Should -BeNullOrEmpty
        }

        It 'Should handle various API error scenarios' {
            $errorTypes = @('400', '401', '403', '404', '429', '500', '503')
            foreach ($errorType in $errorTypes) {
                $result = Test-InvalidAuthentication -Credential $script:invalidCred `
                                                  -ApiUrl $script:TEST_API_URL `
                                                  -ExpectedErrorTypes @($errorType)
                $result | Should -BeTrue
            }
        }
    }

    Context 'Token Expiration' {
        It 'Should detect token expiration with precision timing' {
            $result = Test-ExpiredAuthentication -Credential $script:expiredCred `
                                              -ApiUrl $script:TEST_API_URL `
                                              -ExpirationSeconds 1
            $result | Should -BeTrue
        }

        It 'Should handle refresh scenarios across platforms' {
            foreach ($platform in $script:TEST_PLATFORMS) {
                $result = Test-ExpiredAuthentication -Credential $script:expiredCred `
                                                  -ApiUrl $script:TEST_API_URL `
                                                  -ExpirationSeconds 1
                $result | Should -BeTrue
            }
        }

        It 'Should manage failed refresh with retry logic' {
            $result = Test-ExpiredAuthentication -Credential $script:expiredCred `
                                              -ApiUrl $script:TEST_API_URL `
                                              -ExpirationSeconds 1
            $result | Should -BeTrue
        }
    }

    Context 'SecretStore Integration' {
        It 'Should initialize SecretStore securely per platform' {
            foreach ($platform in $script:TEST_PLATFORMS) {
                $result = Test-SecretStoreIntegration -Credential $script:validCred `
                                                    -Platform $platform
                $result | Should -BeTrue
            }
        }

        It 'Should handle credential encryption correctly' {
            $result = Test-SecretStoreIntegration -Credential $script:validCred
            $result | Should -BeTrue
        }

        It 'Should manage secure credential retrieval' {
            $result = Test-SecretStoreIntegration -Credential $script:validCred
            $result | Should -BeTrue
            $storedCred = Get-Secret -Name "PSCompassOne_Credentials_Windows" -Vault $script:TEST_VAULT_NAME
            $storedCred | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should handle Windows-specific authentication' {
            $result = Test-SecretStoreIntegration -Credential $script:validCred -Platform 'Windows'
            $result | Should -BeTrue
        }

        It 'Should handle Linux-specific authentication' {
            $result = Test-SecretStoreIntegration -Credential $script:validCred -Platform 'Linux'
            $result | Should -BeTrue
        }

        It 'Should handle MacOS-specific authentication' {
            $result = Test-SecretStoreIntegration -Credential $script:validCred -Platform 'MacOS'
            $result | Should -BeTrue
        }
    }

    Context 'Security Audit' {
        It 'Should log all authentication attempts' {
            $logContent = Get-Content $script:SECURITY_LOG_PATH
            $logContent | Should -Not -BeNullOrEmpty
            $logContent | ConvertFrom-Json | Where-Object Event -eq 'Authentication' | Should -Not -BeNullOrEmpty
        }

        It 'Should track credential access' {
            $logContent = Get-Content $script:SECURITY_LOG_PATH
            $logContent | ConvertFrom-Json | Where-Object Event -eq 'SecretStore' | Should -Not -BeNullOrEmpty
        }

        It 'Should monitor token usage' {
            $logContent = Get-Content $script:SECURITY_LOG_PATH
            $logContent | ConvertFrom-Json | Where-Object Event -eq 'TokenRefresh' | Should -Not -BeNullOrEmpty
        }
    }
}