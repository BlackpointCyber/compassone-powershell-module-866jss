#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

BeforeAll {
    # Import test environment setup
    . "$PSScriptRoot/testenv.ps1"
    Import-Module "$PSScriptRoot/test.psm1"
    . "$PSScriptRoot/Mocks/MockHttpClient.ps1"

    # Initialize test environment
    $script:testConfig = Initialize-TestModule -ModulePath "$PSScriptRoot/../PSCompassOne" -UseMocks
    $script:moduleManifestPath = "$PSScriptRoot/../PSCompassOne/PSCompassOne.psd1"
    $script:mockCredentials = Get-Content "$PSScriptRoot/Mocks/TestCredentials.json" | ConvertFrom-Json
    
    # Configure strict mode and error handling
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
}

Describe 'Module Manifest Tests' {
    BeforeAll {
        $script:manifest = Test-ModuleManifest -Path $moduleManifestPath -ErrorAction Stop
    }

    It 'Should have a valid module manifest' {
        $manifest | Should -Not -BeNullOrEmpty
        $manifest.Name | Should -Be 'PSCompassOne'
    }

    It 'Should specify correct PowerShell versions' {
        $manifest.PowerShellVersion | Should -BeGreaterOrEqual '5.1'
        $manifest.CompatiblePSEditions | Should -Contain 'Core'
        $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
    }

    It 'Should list required modules with versions' {
        $manifest.RequiredModules | Should -Contain @{
            ModuleName = 'Microsoft.PowerShell.SecretStore'
            ModuleVersion = '1.0.6'
        }
    }

    It 'Should have valid GUID and version' {
        $manifest.Guid | Should -Not -BeNullOrEmpty
        $manifest.Guid | Should -BeOfType [System.Guid]
        $manifest.Version | Should -BeOfType [System.Version]
    }

    It 'Should have valid author and company information' {
        $manifest.Author | Should -Not -BeNullOrEmpty
        $manifest.CompanyName | Should -Be 'Blackpoint'
        $manifest.Copyright | Should -Not -BeNullOrEmpty
    }

    It 'Should export all required functions' {
        $expectedFunctions = @(
            'Get-CraftAsset',
            'Get-CraftAssetList',
            'New-CraftAsset',
            'Set-CraftAsset',
            'Remove-CraftAsset',
            'Get-CraftFinding',
            'Get-CraftFindingList',
            'New-CraftFinding',
            'Set-CraftFinding',
            'Remove-CraftFinding'
        )
        $manifest.ExportedFunctions.Keys | Should -Contain $expectedFunctions
    }
}

Describe 'Module Loading Tests' {
    BeforeAll {
        Remove-Module PSCompassOne -ErrorAction SilentlyContinue
    }

    It 'Should import without errors on <_>' -ForEach @('Windows', 'Linux', 'MacOS') {
        { Import-Module $moduleManifestPath -Force } | Should -Not -Throw
    }

    It 'Should be available in module list after import' {
        Get-Module PSCompassOne | Should -Not -BeNullOrEmpty
    }

    It 'Should initialize required variables and state' {
        $module = Get-Module PSCompassOne
        $module.SessionState | Should -Not -BeNullOrEmpty
        $module.ExportedCommands.Count | Should -BeGreaterThan 0
    }

    It 'Should configure logging and diagnostics' {
        $logPath = if ($IsWindows) {
            "$env:ProgramData\PSCompassOne\logs"
        } else {
            "/var/log/PSCompassOne"
        }
        Test-Path $logPath | Should -BeTrue
    }
}

Describe 'Security Control Tests' {
    BeforeAll {
        Import-Module $moduleManifestPath -Force
    }

    Context 'TLS Protocol Tests' {
        It 'Should enforce TLS 1.2 or higher' {
            $results = Test-TlsProtocol -ApiUrl $mockCredentials.validCredentials.apiUrl -ExpectedVersion '1.2'
            $results.Compliant | Should -BeTrue
        }

        It 'Should prevent TLS protocol downgrade' {
            $results = Test-TlsProtocol -ApiUrl $mockCredentials.validCredentials.apiUrl -ExpectedVersion '1.2' -DetailedLogging
            $results.Details | Should -Contain 'Downgrade Prevention: Pass'
        }
    }

    Context 'Data Encryption Tests' {
        It 'Should use AES-256 encryption' {
            $results = Test-DataEncryption -Algorithm 'AES-256' -KeySize 256 -AuditLog
            $results.Compliant | Should -BeTrue
            $results.KeyStrength | Should -Be 256
        }

        It 'Should securely store credentials' {
            $secureKey = ConvertTo-SecureString $mockCredentials.validCredentials.apiKey -AsPlainText -Force
            { Set-Secret -Name 'PSCompassOne_TestKey' -SecureValue $secureKey } | Should -Not -Throw
            $storedKey = Get-Secret -Name 'PSCompassOne_TestKey' -AsPlainText
            $storedKey | Should -Be $mockCredentials.validCredentials.apiKey
        }
    }

    Context 'Input Validation Tests' {
        It 'Should validate and sanitize input parameters' {
            $testInput = @{
                AssetId = '00000000-0000-0000-0000-000000000001'
                Name = 'Test Asset'
                Status = 'Active'
            }
            $rules = @('ValidateNotNullOrEmpty', 'ValidatePattern')
            $results = Test-InputValidation -TestInput $testInput -ValidationRules $rules -StrictMode
            $results.Valid | Should -BeTrue
            $results.Violations.Count | Should -Be 0
        }

        It 'Should prevent injection attacks' {
            $testInput = @{
                Name = "Test'; DROP TABLE Assets; --"
                Status = '<script>alert(1)</script>'
            }
            $rules = @('ValidateScript', 'ValidatePattern')
            $results = Test-InputValidation -TestInput $testInput -ValidationRules $rules -StrictMode
            $results.Valid | Should -BeFalse
            $results.SecurityFindings.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Output Security Tests' {
        It 'Should mask sensitive data in output' {
            $outputData = @{
                ApiKey = $mockCredentials.validCredentials.apiKey
                AccountId = $mockCredentials.validCredentials.accountId
                CustomData = @{
                    Password = 'SecretPassword123!'
                }
            }
            $sensitiveFields = @('ApiKey', 'Password')
            $results = Test-SecureOutput -OutputData $outputData -SensitiveFields $sensitiveFields -EnableAudit
            $results.Secure | Should -BeTrue
            $results.Findings.Count | Should -Be 0
        }
    }
}

Describe 'API Integration Tests' {
    BeforeAll {
        $mockClient = New-MockHttpClient
        Add-MockResponse -Method 'GET' -Uri '*/assets/*' -Response $script:ApiResponses.successResponses.getAssetResponse
    }

    Context 'API Request Tests' {
        It 'Should create valid API requests' {
            $request = @{
                Method = 'GET'
                Uri = 'https://api.test.compassone.com/v1/assets/123'
                Headers = @{
                    'Content-Type' = 'application/json'
                    'Authorization' = "Bearer $($mockCredentials.validCredentials.apiKey)"
                }
            }
            Assert-ApiCallMade -MockHttpClient $mockClient -ExpectedMethod 'GET' -ExpectedUri '*/assets/*' -ExpectedHeaders $request.Headers
        }

        It 'Should handle API responses correctly' {
            $response = Invoke-MockRequest -Method 'GET' -Uri 'https://api.test.compassone.com/v1/assets/123'
            Test-ApiResponseStatus -Response $response -ExpectedStatus 200 | Should -BeTrue
            Test-ApiResponseHeaders -Response $response -ExpectedHeaders @{
                'Content-Type' = 'application/json'
                'API-Version' = 'v1'
            } | Should -BeTrue
        }

        It 'Should implement proper error handling' {
            Add-MockResponse -Method 'GET' -Uri '*/assets/invalid' -Response $script:ApiResponses.errorResponses.notFoundResponse
            $response = Invoke-MockRequest -Method 'GET' -Uri 'https://api.test.compassone.com/v1/assets/invalid'
            Test-ApiErrorResponse -Response $response -ExpectedErrorCode 'NotFound' | Should -BeTrue
        }
    }
}

AfterAll {
    # Clean up test environment
    Remove-Module PSCompassOne -ErrorAction SilentlyContinue
    Reset-TestSetup
    Remove-Item -Path "$env:TEMP\PSCompassOne" -Recurse -Force -ErrorAction SilentlyContinue
}