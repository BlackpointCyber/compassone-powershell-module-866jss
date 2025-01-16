using module Microsoft.PowerShell.Utility # Version 5.1.0+
using module Pester # Version 5.3.0+

BeforeAll {
    # Import test helper functions
    . "$PSScriptRoot/TestHelpers/Assert-ApiCall.ps1"
    . "$PSScriptRoot/Mocks/MockHttpClient.ps1"

    # Load test data
    $script:TestData = @{
        Assets = Get-Content "$PSScriptRoot/Mocks/AssetData.json" | ConvertFrom-Json
        Findings = Get-Content "$PSScriptRoot/Mocks/FindingData.json" | ConvertFrom-Json
        ApiResponses = Get-Content "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
    }

    # Initialize test environment
    $script:TestConfig = @{
        BaseUrl = 'https://api.compassone.com'
        ApiVersion = 'v1'
        DefaultTimeout = 30
        MaxRetries = 3
        RetryDelays = @(1, 2, 4)
    }

    $script:MockClient = New-MockHttpClient -Configuration @{
        DefaultTimeout = $TestConfig.DefaultTimeout
        MaxRetries = $TestConfig.MaxRetries
        SimulateLatency = $false
        EnableRequestLogging = $true
        ValidateResponses = $true
    }
}

BeforeEach {
    # Reset mock state before each test
    Clear-MockResponses
}

Describe 'API Client Initialization' {
    Context 'Valid Configuration' {
        It 'Should initialize with valid configuration' {
            $config = @{
                BaseUrl = $TestConfig.BaseUrl
                ApiVersion = $TestConfig.ApiVersion
                Timeout = $TestConfig.DefaultTimeout
            }

            { Initialize-ApiClient -Configuration $config } | Should -Not -Throw
            $client = Get-ApiClient
            $client | Should -Not -BeNull
            $client.BaseUrl | Should -Be $TestConfig.BaseUrl
            $client.ApiVersion | Should -Be $TestConfig.ApiVersion
        }

        It 'Should use default values for optional parameters' {
            $config = @{
                BaseUrl = $TestConfig.BaseUrl
            }

            { Initialize-ApiClient -Configuration $config } | Should -Not -Throw
            $client = Get-ApiClient
            $client.Timeout | Should -Be 30
            $client.MaxRetries | Should -Be 3
        }
    }

    Context 'Invalid Configuration' {
        It 'Should throw on missing base URL' {
            $config = @{
                ApiVersion = $TestConfig.ApiVersion
            }

            { Initialize-ApiClient -Configuration $config } | Should -Throw -ErrorId 'PSCompassOne.InvalidConfiguration'
        }

        It 'Should throw on invalid timeout value' {
            $config = @{
                BaseUrl = $TestConfig.BaseUrl
                Timeout = -1
            }

            { Initialize-ApiClient -Configuration $config } | Should -Throw -ErrorId 'PSCompassOne.InvalidConfiguration'
        }
    }
}

Describe 'Request Handling' {
    Context 'GET Requests' {
        It 'Should handle GET request with query parameters' {
            $mockResponse = $TestData.ApiResponses.successResponses.getAssetResponse
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            $params = @{
                PageSize = 50
                SortBy = 'name'
                Filter = 'status eq "Active"'
            }

            $response = Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' -Parameters $params
            Assert-ApiCallMade -MockHttpClient $script:MockClient -ExpectedMethod 'GET' -ExpectedUri "$($TestConfig.BaseUrl)/v1/assets"
            $response.statusCode | Should -Be 200
        }

        It 'Should properly encode query parameters' {
            $params = @{
                Filter = 'name eq "Test Server" and status eq "Active"'
            }

            Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' -Parameters $params
            Assert-ApiCallMade -MockHttpClient $script:MockClient -ExpectedMethod 'GET' -ExpectedUri "$($TestConfig.BaseUrl)/v1/assets?Filter=name%20eq%20%22Test%20Server%22%20and%20status%20eq%20%22Active%22"
        }
    }

    Context 'POST Requests' {
        It 'Should handle POST request with JSON body' {
            $asset = $TestData.Assets.singleAsset
            $mockResponse = $TestData.ApiResponses.successResponses.getAssetResponse

            Add-MockResponse -Method 'POST' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            $response = Invoke-ApiRequest -Method 'POST' -Endpoint 'assets' -Body $asset
            Assert-ApiCallMade -MockHttpClient $script:MockClient -ExpectedMethod 'POST' -ExpectedUri "$($TestConfig.BaseUrl)/v1/assets" -ExpectedBody $asset
            $response.statusCode | Should -Be 200
        }

        It 'Should validate request body before sending' {
            $invalidBody = @{ invalid = $true }
            { Invoke-ApiRequest -Method 'POST' -Endpoint 'assets' -Body $invalidBody } | Should -Throw -ErrorId 'PSCompassOne.InvalidRequest'
        }
    }
}

Describe 'Response Processing' {
    Context 'Success Responses' {
        It 'Should properly parse JSON response' {
            $mockResponse = $TestData.ApiResponses.successResponses.getAssetResponse
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets/test" -Response $mockResponse

            $response = Invoke-ApiRequest -Method 'GET' -Endpoint 'assets/test'
            $response.body.data | Should -Not -BeNull
            $response.body.data.id | Should -Be $mockResponse.body.data.id
        }

        It 'Should handle empty response bodies' {
            $mockResponse = @{
                statusCode = 204
                headers = @{ 'Content-Type' = 'application/json' }
                body = $null
            }
            Add-MockResponse -Method 'DELETE' -Uri "$($TestConfig.BaseUrl)/v1/assets/test" -Response $mockResponse

            $response = Invoke-ApiRequest -Method 'DELETE' -Endpoint 'assets/test'
            $response.statusCode | Should -Be 204
            $response.body | Should -BeNull
        }
    }

    Context 'Error Responses' {
        It 'Should handle 400 Bad Request errors' {
            $mockResponse = $TestData.ApiResponses.errorResponses.badRequestResponse
            Add-MockResponse -Method 'POST' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            { Invoke-ApiRequest -Method 'POST' -Endpoint 'assets' -Body @{} } | Should -Throw -ErrorId 'PSCompassOne.BadRequest'
        }

        It 'Should handle 401 Unauthorized errors' {
            $mockResponse = $TestData.ApiResponses.errorResponses.unauthorizedResponse
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            { Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' } | Should -Throw -ErrorId 'PSCompassOne.Unauthorized'
        }

        It 'Should handle 429 Rate Limit errors with retry' {
            $mockResponse = $TestData.ApiResponses.errorResponses.rateLimitResponse
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            { Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' } | Should -Throw -ErrorId 'PSCompassOne.RateLimit'
            Assert-ApiCallCount -MockHttpClient $script:MockClient -ExpectedCount $TestConfig.MaxRetries
        }
    }
}

Describe 'Authentication' {
    Context 'Token Authentication' {
        It 'Should include authentication token in requests' {
            $token = 'test-token-123'
            Initialize-ApiClient -Configuration @{
                BaseUrl = $TestConfig.BaseUrl
                Token = $token
            }

            Invoke-ApiRequest -Method 'GET' -Endpoint 'assets'
            Assert-ApiCallMade -MockHttpClient $script:MockClient -ExpectedMethod 'GET' -ExpectedUri "$($TestConfig.BaseUrl)/v1/assets" -ExpectedHeaders @{
                'Authorization' = "Bearer $token"
            }
        }

        It 'Should handle token refresh' {
            $mockResponse = $TestData.ApiResponses.errorResponses.unauthorizedResponse
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            Mock -CommandName Get-StoredToken -MockWith { 'new-token-456' }

            Invoke-ApiRequest -Method 'GET' -Endpoint 'assets'
            Assert-ApiCallMade -MockHttpClient $script:MockClient -ExpectedMethod 'GET' -ExpectedUri "$($TestConfig.BaseUrl)/v1/assets" -ExpectedHeaders @{
                'Authorization' = 'Bearer new-token-456'
            }
        }
    }
}

Describe 'Retry Logic' {
    Context 'Network Errors' {
        It 'Should retry on network timeout' {
            $mockResponse = @{
                statusCode = 503
                error = @{ message = 'Service Unavailable' }
            }
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            { Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' } | Should -Throw
            Assert-ApiCallCount -MockHttpClient $script:MockClient -ExpectedCount $TestConfig.MaxRetries
        }

        It 'Should use exponential backoff' {
            $mockResponse = $TestData.ApiResponses.errorResponses.rateLimitResponse
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            $startTime = Get-Date
            { Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' } | Should -Throw
            $duration = (Get-Date) - $startTime

            # Verify minimum delay based on retry delays (1 + 2 + 4 seconds)
            $duration.TotalSeconds | Should -BeGreaterThan 7
        }
    }

    Context 'Success After Retry' {
        It 'Should succeed after temporary failure' {
            $errorResponse = $TestData.ApiResponses.errorResponses.rateLimitResponse
            $successResponse = $TestData.ApiResponses.successResponses.getAssetResponse

            # First call fails, second succeeds
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $errorResponse
            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $successResponse

            $response = Invoke-ApiRequest -Method 'GET' -Endpoint 'assets'
            $response.statusCode | Should -Be 200
            Assert-ApiCallCount -MockHttpClient $script:MockClient -ExpectedCount 2
        }
    }
}

Describe 'Security Controls' {
    Context 'Request Security' {
        It 'Should enforce HTTPS' {
            $config = @{
                BaseUrl = 'http://api.compassone.com'
            }

            { Initialize-ApiClient -Configuration $config } | Should -Throw -ErrorId 'PSCompassOne.InvalidConfiguration'
        }

        It 'Should validate request parameters' {
            $params = @{
                'malicious;command' = 'value'
            }

            { Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' -Parameters $params } | Should -Throw -ErrorId 'PSCompassOne.InvalidRequest'
        }
    }

    Context 'Response Security' {
        It 'Should validate response content type' {
            $mockResponse = $TestData.ApiResponses.successResponses.getAssetResponse
            $mockResponse.headers.'Content-Type' = 'text/plain'

            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            { Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' } | Should -Throw -ErrorId 'PSCompassOne.InvalidResponse'
        }

        It 'Should handle malformed JSON responses' {
            $mockResponse = @{
                statusCode = 200
                headers = @{ 'Content-Type' = 'application/json' }
                body = 'invalid json {'
            }

            Add-MockResponse -Method 'GET' -Uri "$($TestConfig.BaseUrl)/v1/assets" -Response $mockResponse

            { Invoke-ApiRequest -Method 'GET' -Endpoint 'assets' } | Should -Throw -ErrorId 'PSCompassOne.InvalidResponse'
        }
    }
}