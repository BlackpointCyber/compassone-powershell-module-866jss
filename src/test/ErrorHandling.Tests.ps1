#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }

using namespace System.Net.Http

BeforeAll {
    # Import test helper functions
    . "$PSScriptRoot/TestHelpers/Test-ErrorHandling.ps1"

    # Import mock response data
    $script:ErrorResponses = Get-Content -Path "$PSScriptRoot/Mocks/ErrorResponses.json" | ConvertFrom-Json
    $script:ApiResponses = Get-Content -Path "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
}

Describe 'Error Handling Tests' {
    Context 'Error Response Validation' {
        It 'Should properly handle 400 Bad Request errors' {
            $response = $ErrorResponses.badRequestResponse
            $result = Test-ErrorResponse -Response $response `
                                      -ExpectedStatusCode $HTTP_ERROR_CODES.BAD_REQUEST `
                                      -ExpectedCategory 'InvalidArgument'
            $result | Should -BeTrue
        }

        It 'Should properly handle 401 Unauthorized errors' {
            $response = $ErrorResponses.unauthorizedResponse
            $result = Test-ErrorResponse -Response $response `
                                      -ExpectedStatusCode $HTTP_ERROR_CODES.UNAUTHORIZED `
                                      -ExpectedCategory 'SecurityError'
            $result | Should -BeTrue
        }

        It 'Should properly handle 403 Forbidden errors' {
            $response = $ErrorResponses.forbiddenResponse
            $result = Test-ErrorResponse -Response $response `
                                      -ExpectedStatusCode $HTTP_ERROR_CODES.FORBIDDEN `
                                      -ExpectedCategory 'PermissionDenied'
            $result | Should -BeTrue
        }

        It 'Should properly handle 404 Not Found errors' {
            $response = $ErrorResponses.notFoundResponse
            $result = Test-ErrorResponse -Response $response `
                                      -ExpectedStatusCode $HTTP_ERROR_CODES.NOT_FOUND `
                                      -ExpectedCategory 'ObjectNotFound'
            $result | Should -BeTrue
        }

        It 'Should properly handle 429 Rate Limit errors' {
            $response = $ErrorResponses.rateLimitResponse
            $result = Test-ErrorResponse -Response $response `
                                      -ExpectedStatusCode $HTTP_ERROR_CODES.RATE_LIMIT `
                                      -ExpectedCategory 'LimitsExceeded'
            $result | Should -BeTrue
        }

        It 'Should properly handle 500 Server Error errors' {
            $response = $ErrorResponses.serverErrorResponse
            $result = Test-ErrorResponse -Response $response `
                                      -ExpectedStatusCode $HTTP_ERROR_CODES.SERVER_ERROR `
                                      -ExpectedCategory 'InvalidOperation'
            $result | Should -BeTrue
        }

        It 'Should properly handle 503 Service Unavailable errors' {
            $response = $ErrorResponses.serviceUnavailableResponse
            $result = Test-ErrorResponse -Response $response `
                                      -ExpectedStatusCode $HTTP_ERROR_CODES.SERVICE_UNAVAILABLE `
                                      -ExpectedCategory 'ConnectionError'
            $result | Should -BeTrue
        }
    }

    Context 'Retry Behavior' {
        It 'Should implement retry logic for rate limit errors' {
            $response = $ErrorResponses.rateLimitResponse
            $result = Test-RetryBehavior -Response $response -ExpectedRetries 3
            $result | Should -BeTrue
        }

        It 'Should implement retry logic for server errors' {
            $response = $ErrorResponses.serverErrorResponse
            $result = Test-RetryBehavior -Response $response -ExpectedRetries 3
            $result | Should -BeTrue
        }

        It 'Should implement retry logic for service unavailable errors' {
            $response = $ErrorResponses.serviceUnavailableResponse
            $result = Test-RetryBehavior -Response $response -ExpectedRetries 3
            $result | Should -BeTrue
        }

        It 'Should not retry on non-retryable errors' {
            $response = $ErrorResponses.badRequestResponse
            $result = Test-RetryBehavior -Response $response -ExpectedRetries 0
            $result | Should -BeTrue
        }

        It 'Should respect Retry-After headers' {
            $response = $ErrorResponses.rateLimitResponse
            $response.Headers['Retry-After'] | Should -Not -BeNullOrEmpty
            [int]::TryParse($response.Headers['Retry-After'], [ref]$null) | Should -BeTrue
        }
    }

    Context 'Error Category Mapping' {
        It 'Should map 400 to InvalidArgument category' {
            $result = Test-ErrorCategory -StatusCode 400 -ExpectedCategory 'InvalidArgument'
            $result | Should -BeTrue
        }

        It 'Should map 401 to SecurityError category' {
            $result = Test-ErrorCategory -StatusCode 401 -ExpectedCategory 'SecurityError'
            $result | Should -BeTrue
        }

        It 'Should map 403 to PermissionDenied category' {
            $result = Test-ErrorCategory -StatusCode 403 -ExpectedCategory 'PermissionDenied'
            $result | Should -BeTrue
        }

        It 'Should map 404 to ObjectNotFound category' {
            $result = Test-ErrorCategory -StatusCode 404 -ExpectedCategory 'ObjectNotFound'
            $result | Should -BeTrue
        }

        It 'Should map 429 to LimitsExceeded category' {
            $result = Test-ErrorCategory -StatusCode 429 -ExpectedCategory 'LimitsExceeded'
            $result | Should -BeTrue
        }

        It 'Should map 500 to InvalidOperation category' {
            $result = Test-ErrorCategory -StatusCode 500 -ExpectedCategory 'InvalidOperation'
            $result | Should -BeTrue
        }

        It 'Should map 503 to ConnectionError category' {
            $result = Test-ErrorCategory -StatusCode 503 -ExpectedCategory 'ConnectionError'
            $result | Should -BeTrue
        }
    }

    Context 'Security Error Handling' {
        It 'Should properly handle authentication errors' {
            $response = $ErrorResponses.unauthorizedResponse
            $result = Test-SecurityError -Response $response -ErrorType 'Authentication'
            $result | Should -BeTrue
        }

        It 'Should properly handle authorization errors' {
            $response = $ErrorResponses.forbiddenResponse
            $result = Test-SecurityError -Response $response -ErrorType 'Authorization'
            $result | Should -BeTrue
        }

        It 'Should include security-specific headers in responses' {
            $response = $ErrorResponses.unauthorizedResponse
            $response.Headers['X-Error-Source'] | Should -Not -BeNullOrEmpty
            $response.Headers['Request-Id'] | Should -Not -BeNullOrEmpty
        }

        It 'Should mark security errors as terminating' {
            $response = $ErrorResponses.unauthorizedResponse
            $response.error.powerShell.isTerminating | Should -BeTrue
        }

        It 'Should include troubleshooting information for security errors' {
            $response = $ErrorResponses.unauthorizedResponse
            $response.error.powerShell.troubleshooting | Should -Not -BeNullOrEmpty
            $response.error.powerShell.recommendedAction | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error Message Formatting' {
        It 'Should include error code in message' {
            $response = $ErrorResponses.badRequestResponse
            $response.error.code | Should -Not -BeNullOrEmpty
        }

        It 'Should include descriptive error message' {
            $response = $ErrorResponses.badRequestResponse
            $response.error.message | Should -Not -BeNullOrEmpty
        }

        It 'Should include error details when available' {
            $response = $ErrorResponses.badRequestResponse
            $response.error.details | Should -Not -BeNullOrEmpty
        }

        It 'Should include PowerShell-specific error metadata' {
            $response = $ErrorResponses.badRequestResponse
            $response.error.powerShell | Should -Not -BeNullOrEmpty
            $response.error.powerShell.errorCategory | Should -Not -BeNullOrEmpty
            $response.error.powerShell.errorId | Should -Not -BeNullOrEmpty
        }
    }
}