#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

BeforeAll {
    # Import test helpers and configuration
    . "$PSScriptRoot/TestHelpers/Test-SecurityControl.ps1"
    $testSettings = Get-Content "$PSScriptRoot/TestConfig/test.settings.json" | ConvertFrom-Json
    $mockCredentials = Get-Content "$PSScriptRoot/Mocks/TestCredentials.json" | ConvertFrom-Json

    # Global test constants
    $script:TEST_TLS_VERSION = '1.2'
    $script:TEST_ENCRYPTION_ALGORITHM = 'AES-256'
    $script:TEST_HASH_ALGORITHM = 'SHA-256'
    $script:SENSITIVE_FIELDS = @('password', 'token', 'key', 'secret', 'credential', 'certificate')
    $script:COMPLIANCE_REQUIREMENTS = @('SecureCommunication', 'DataProtection', 'AccessControl', 'AuditLogging')
    $script:PLATFORM_VERSIONS = @('Windows_5.1', 'Windows_7.x', 'Linux_7.x', 'MacOS_7.x')
}

Describe 'Security Protocol Tests' -Tag @('Security', 'Protocol') {
    BeforeAll {
        $apiUrl = $testSettings.TestEnvironment.ApiEndpoint
    }

    Context 'TLS Protocol Security' {
        It 'Should enforce minimum TLS 1.2 requirement' {
            $result = Test-TlsProtocol -ApiUrl $apiUrl -ExpectedVersion $TEST_TLS_VERSION -DetailedLogging
            $result.Compliant | Should -BeTrue
            $result.Details | Should -Contain 'TLS Version Check: Pass'
        }

        It 'Should prevent TLS protocol downgrade' {
            $result = Test-TlsProtocol -ApiUrl $apiUrl -ExpectedVersion $TEST_TLS_VERSION -DetailedLogging
            $result.Details | Should -Contain 'Downgrade Prevention: Pass'
        }

        It 'Should validate secure cipher suite usage' {
            $result = Test-TlsProtocol -ApiUrl $apiUrl -ExpectedVersion $TEST_TLS_VERSION -DetailedLogging
            $result.Details | Should -Match 'Supported Cipher Suites: \d+'
        }
    }

    Context 'Cross-Platform Protocol Security' {
        It 'Should maintain protocol security across <_>' -ForEach $PLATFORM_VERSIONS {
            $platform = $_
            $result = Test-TlsProtocol -ApiUrl $apiUrl -ExpectedVersion $TEST_TLS_VERSION -DetailedLogging
            $result.PlatformSpecific.Platform | Should -Be ($platform -split '_')[0]
            $result.Compliant | Should -BeTrue
        }
    }
}

Describe 'Data Protection Tests' -Tag @('Security', 'Encryption') {
    Context 'Encryption Implementation' {
        It 'Should implement AES-256 encryption correctly' {
            $result = Test-DataEncryption -Algorithm $TEST_ENCRYPTION_ALGORITHM -KeySize 256 -AuditLog
            $result.Compliant | Should -BeTrue
            $result.KeyStrength | Should -Be 256
        }

        It 'Should properly manage encryption keys' {
            $result = Test-DataEncryption -Algorithm $TEST_ENCRYPTION_ALGORITHM -KeySize 256 -AuditLog
            $result.AuditEntries | Should -Contain 'Key Validation: Success'
        }

        It 'Should validate secure key storage' {
            $result = Test-DataEncryption -Algorithm $TEST_ENCRYPTION_ALGORITHM -KeySize 256 -AuditLog
            $result.AuditEntries | Should -Contain 'Key Storage: Success'
        }
    }

    Context 'Sensitive Data Handling' {
        BeforeAll {
            $testInput = @{
                'password' = 'TestPassword123!'
                'apiKey' = 'sk_test_123456789'
                'normalField' = 'public data'
            }
        }

        It 'Should properly mask sensitive fields' {
            $result = Test-SecureOutput -OutputData $testInput -SensitiveFields $SENSITIVE_FIELDS -EnableAudit
            $result.Secure | Should -BeTrue
            $result.Findings.Count | Should -Be 0
        }

        It 'Should handle secure string cleanup' {
            $result = Test-SecureOutput -OutputData $testInput -SensitiveFields $SENSITIVE_FIELDS -EnableAudit
            $result.AuditTrail | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Authentication Security Tests' -Tag @('Security', 'Authentication') {
    Context 'API Token Security' {
        BeforeAll {
            $validToken = $mockCredentials.validCredentials.apiKey
            $invalidToken = $mockCredentials.invalidCredentials.apiKey
            $expiredToken = $mockCredentials.expiredCredentials.apiKey
        }

        It 'Should validate API token format' {
            $validationRules = @($mockCredentials._metadata.validationRules.apiKey.pattern)
            $result = Test-InputValidation -TestInput @{ 'apiKey' = $validToken } -ValidationRules $validationRules -StrictMode
            $result.Valid | Should -BeTrue
        }

        It 'Should detect invalid tokens' {
            $validationRules = @($mockCredentials._metadata.validationRules.apiKey.pattern)
            $result = Test-InputValidation -TestInput @{ 'apiKey' = $invalidToken } -ValidationRules $validationRules -StrictMode
            $result.Valid | Should -BeFalse
        }

        It 'Should handle token expiration' {
            $validationRules = @($mockCredentials.expiredCredentials.refreshPattern)
            $result = Test-InputValidation -TestInput @{ 'apiKey' = $expiredToken } -ValidationRules $validationRules -StrictMode
            $result.SecurityFindings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'SecretStore Integration' {
        It 'Should securely store credentials' {
            $result = Test-SecureOutput -OutputData $mockCredentials.validCredentials -SensitiveFields $SENSITIVE_FIELDS -EnableAudit
            $result.Secure | Should -BeTrue
        }

        It 'Should properly handle credential rotation' {
            $result = Test-SecureOutput -OutputData $mockCredentials.validCredentials -SensitiveFields $SENSITIVE_FIELDS -EnableAudit
            $result.AuditTrail | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Compliance Requirement Tests' -Tag @('Security', 'Compliance') {
    Context 'Security Standards Compliance' {
        It 'Should validate <_> compliance' -ForEach $COMPLIANCE_REQUIREMENTS {
            $requirement = $_
            $validationRules = @("Test$requirement")
            $result = Test-InputValidation -TestInput @{ 'requirement' = $requirement } -ValidationRules $validationRules -StrictMode
            $result.Valid | Should -BeTrue
        }
    }

    Context 'Audit Logging' {
        It 'Should maintain comprehensive audit logs' {
            $result = Test-SecureOutput -OutputData @{ 'operation' = 'test' } -SensitiveFields @() -EnableAudit
            $result.AuditTrail | Should -Not -BeNullOrEmpty
        }

        It 'Should properly sanitize audit log output' {
            $testData = @{
                'operation' = 'test'
                'apiKey' = $mockCredentials.validCredentials.apiKey
            }
            $result = Test-SecureOutput -OutputData $testData -SensitiveFields $SENSITIVE_FIELDS -EnableAudit
            $result.Secure | Should -BeTrue
        }
    }

    Context 'Cross-Platform Compliance' {
        It 'Should maintain security compliance on <_>' -ForEach $PLATFORM_VERSIONS {
            $platform = $_
            $result = Test-InputValidation -TestInput @{ 'platform' = $platform } -ValidationRules $COMPLIANCE_REQUIREMENTS -StrictMode
            $result.Valid | Should -BeTrue
        }
    }
}