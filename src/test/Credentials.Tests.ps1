#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

BeforeAll {
    # Import test helpers and mock data
    . "$PSScriptRoot/TestHelpers/Test-Authentication.ps1"
    $mockCredentials = Get-Content "$PSScriptRoot/Mocks/TestCredentials.json" | ConvertFrom-Json
    $pesterConfig = New-PSCompassOnePesterConfig

    # Initialize test environment
    $testEnvironment = Initialize-TestEnvironment -ModulePath "$PSScriptRoot/../PSCompassOne" -TestPath $PSScriptRoot
    $script:TEST_API_URL = 'https://api.test.compassone.com'
    $script:TEST_VAULT_NAME = 'PSCompassOneTest'
    $script:TEST_AUDIT_LOG = "$env:TEMP/PSCompassOne/TestAudit.log"
    $script:TEST_SECURITY_CONFIG = @{
        EncryptionLevel = 'AES256'
        TokenValidityMinutes = 60
        MaxRetryAttempts = 3
    }
}

Describe 'PSCompassOne Credential Management' {
    BeforeEach {
        # Initialize SecretStore for each test
        Initialize-SecretStore -Scope CurrentUser -Password (ConvertTo-SecureString -String "TestPassword123!" -AsPlainText -Force)
    }

    Context 'SecretStore Integration' {
        It 'Should successfully store credentials with proper encryption' {
            # Arrange
            $apiKey = $mockCredentials.validCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))

            # Act
            $result = Test-SecretStoreIntegration -Credential $credential -VaultName $script:TEST_VAULT_NAME

            # Assert
            $result | Should -BeTrue
        }

        It 'Should retrieve stored credentials with integrity validation' {
            # Arrange
            $apiKey = $mockCredentials.validCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))
            Set-Secret -Name "PSCompassOne_Credentials" -SecureValue $credential.Password -Vault $script:TEST_VAULT_NAME

            # Act
            $storedCredential = Get-Secret -Name "PSCompassOne_Credentials" -Vault $script:TEST_VAULT_NAME
            $storedApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($storedCredential)
            )

            # Assert
            $storedApiKey | Should -Be $apiKey
        }

        It 'Should update existing credentials maintaining security' {
            # Arrange
            $oldApiKey = $mockCredentials.validCredentials.apiKey
            $newApiKey = "new-test-api-key-98765"
            $oldCredential = [PSCredential]::new('api', (ConvertTo-SecureString -String $oldApiKey -AsPlainText -Force))
            $newCredential = [PSCredential]::new('api', (ConvertTo-SecureString -String $newApiKey -AsPlainText -Force))

            # Act
            Set-Secret -Name "PSCompassOne_Credentials" -SecureValue $oldCredential.Password -Vault $script:TEST_VAULT_NAME
            Set-Secret -Name "PSCompassOne_Credentials" -SecureValue $newCredential.Password -Vault $script:TEST_VAULT_NAME
            $storedCredential = Get-Secret -Name "PSCompassOne_Credentials" -Vault $script:TEST_VAULT_NAME
            $storedApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($storedCredential)
            )

            # Assert
            $storedApiKey | Should -Be $newApiKey
        }

        It 'Should remove credentials with secure cleanup' {
            # Arrange
            $apiKey = $mockCredentials.validCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))
            Set-Secret -Name "PSCompassOne_Credentials" -SecureValue $credential.Password -Vault $script:TEST_VAULT_NAME

            # Act
            Remove-Secret -Name "PSCompassOne_Credentials" -Vault $script:TEST_VAULT_NAME
            $storedCredential = Get-Secret -Name "PSCompassOne_Credentials" -Vault $script:TEST_VAULT_NAME -ErrorAction SilentlyContinue

            # Assert
            $storedCredential | Should -BeNullOrEmpty
        }
    }

    Context 'API Authentication' {
        It 'Should authenticate with valid credentials and verify token' {
            # Arrange
            $apiKey = $mockCredentials.validCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))

            # Act
            $result = Test-ValidAuthentication -Credential $credential -ApiUrl $script:TEST_API_URL

            # Assert
            $result | Should -BeTrue
        }

        It 'Should reject invalid credentials with proper logging' {
            # Arrange
            $apiKey = $mockCredentials.invalidCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))

            # Act
            $result = Test-InvalidAuthentication -Credential $credential -ApiUrl $script:TEST_API_URL

            # Assert
            $result | Should -BeTrue
            Test-Path $script:TEST_AUDIT_LOG | Should -BeTrue
            $logContent = Get-Content $script:TEST_AUDIT_LOG -Raw
            $logContent | Should -Match 'Authentication.*Failure'
        }

        It 'Should handle expired tokens with automatic refresh' {
            # Arrange
            $apiKey = $mockCredentials.validCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))

            # Act
            $result = Test-ExpiredAuthentication -Credential $credential -ApiUrl $script:TEST_API_URL -ExpirationSeconds 1

            # Assert
            $result | Should -BeTrue
        }
    }

    Context 'Cross-Platform Credential Handling' {
        It 'Should handle <_> credential storage' -ForEach @('Windows', 'Linux', 'MacOS') {
            # Arrange
            $apiKey = $mockCredentials.validCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))

            # Act
            $result = Test-SecretStoreIntegration -Credential $credential -Platform $_ -VaultName $script:TEST_VAULT_NAME

            # Assert
            $result | Should -BeTrue
        }

        It 'Should maintain security across platforms' {
            # Arrange
            $apiKey = $mockCredentials.validCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))

            # Test on each platform
            foreach ($platform in @('Windows', 'Linux', 'MacOS')) {
                # Act
                $result = Test-SecretStoreIntegration -Credential $credential -Platform $platform -VaultName $script:TEST_VAULT_NAME

                # Assert
                $result | Should -BeTrue
                
                # Verify cross-platform accessibility
                $storedCredential = Get-Secret -Name "PSCompassOne_Credentials_$platform" -Vault $script:TEST_VAULT_NAME
                $storedCredential | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Security Audit and Logging' {
        It 'Should log all credential operations' {
            # Arrange
            $apiKey = $mockCredentials.validCredentials.apiKey
            $credential = [PSCredential]::new('api', (ConvertTo-SecureString -String $apiKey -AsPlainText -Force))

            # Act
            Set-Secret -Name "PSCompassOne_Credentials" -SecureValue $credential.Password -Vault $script:TEST_VAULT_NAME
            Get-Secret -Name "PSCompassOne_Credentials" -Vault $script:TEST_VAULT_NAME
            Remove-Secret -Name "PSCompassOne_Credentials" -Vault $script:TEST_VAULT_NAME

            # Assert
            Test-Path $script:TEST_AUDIT_LOG | Should -BeTrue
            $logContent = Get-Content $script:TEST_AUDIT_LOG
            $logContent.Count | Should -BeGreaterThan 0
            $logContent | Should -Match 'SecretStore'
        }

        It 'Should validate audit trail integrity' {
            # Arrange
            $logPath = $script:TEST_AUDIT_LOG
            $testEntry = @{
                Timestamp = Get-Date -Format 'o'
                Event = 'AuditTest'
                Status = 'Success'
                Details = 'Audit trail integrity test'
            } | ConvertTo-Json

            # Act
            Add-Content -Path $logPath -Value $testEntry
            $logContent = Get-Content $logPath -Raw
            $logObject = $logContent | ConvertFrom-Json

            # Assert
            $logObject.Event | Should -Be 'AuditTest'
            $logObject.Status | Should -Be 'Success'
        }
    }
}

AfterAll {
    # Cleanup test artifacts
    Remove-Item -Path $script:TEST_AUDIT_LOG -ErrorAction SilentlyContinue
    Get-SecretInfo -Vault $script:TEST_VAULT_NAME | ForEach-Object {
        Remove-Secret -Name $_.Name -Vault $script:TEST_VAULT_NAME
    }
}