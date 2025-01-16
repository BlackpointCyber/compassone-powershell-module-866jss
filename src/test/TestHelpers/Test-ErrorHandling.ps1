#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }

using namespace System.Net.Http

<#
.SYNOPSIS
    Provides comprehensive test functions for validating error handling in PSCompassOne.
.DESCRIPTION
    Implements test functions for validating HTTP error responses, retry behavior,
    error category mappings, and security-specific error scenarios across the PSCompassOne module.
#>

# Import error response templates
$script:ErrorResponses = Get-Content -Path "$PSScriptRoot/../Mocks/ErrorResponses.json" | ConvertFrom-Json

# Import mock response helper
. "$PSScriptRoot/New-MockResponse.ps1"

# HTTP Status Code Constants
Set-Variable -Name HTTP_ERROR_CODES -Option Constant -Value @{
    BAD_REQUEST = 400
    UNAUTHORIZED = 401
    FORBIDDEN = 403
    NOT_FOUND = 404
    RATE_LIMIT = 429
    SERVER_ERROR = 500
    SERVICE_UNAVAILABLE = 503
}

# PowerShell Error Category Mappings
Set-Variable -Name ERROR_CATEGORIES -Option Constant -Value @{
    '400' = 'InvalidArgument'
    '401' = 'SecurityError'
    '403' = 'PermissionDenied'
    '404' = 'ObjectNotFound'
    '429' = 'LimitsExceeded'
    '500' = 'InvalidOperation'
    '503' = 'ConnectionError'
}

function Test-ErrorResponse {
    <#
    .SYNOPSIS
        Tests if an API error response is handled correctly according to its status code.
    .PARAMETER Response
        The API response object to test.
    .PARAMETER ExpectedStatusCode
        The expected HTTP status code.
    .PARAMETER ExpectedCategory
        The expected PowerShell error category.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [ValidateRange(400, 599)]
        [int]$ExpectedStatusCode,

        [Parameter(Mandatory)]
        [ValidateSet('InvalidArgument', 'SecurityError', 'PermissionDenied', 
                    'ObjectNotFound', 'LimitsExceeded', 'InvalidOperation', 'ConnectionError')]
        [string]$ExpectedCategory
    )

    # Validate response structure
    if (-not $Response.StatusCode -or -not $Response.Headers -or -not $Response.error) {
        Write-Error "Invalid response structure"
        return $false
    }

    # Check status code
    if ($Response.StatusCode -ne $ExpectedStatusCode) {
        Write-Error "Status code mismatch. Expected: $ExpectedStatusCode, Got: $($Response.StatusCode)"
        return $false
    }

    # Validate error category mapping
    $actualCategory = $ERROR_CATEGORIES[$Response.StatusCode.ToString()]
    if ($actualCategory -ne $ExpectedCategory) {
        Write-Error "Error category mismatch. Expected: $ExpectedCategory, Got: $actualCategory"
        return $false
    }

    # Validate error response format
    $requiredHeaders = @('Content-Type', 'Request-Id', 'X-Error-Source')
    foreach ($header in $requiredHeaders) {
        if (-not $Response.Headers.ContainsKey($header)) {
            Write-Error "Missing required header: $header"
            return $false
        }
    }

    # Validate error details
    if (-not $Response.error.code -or -not $Response.error.message) {
        Write-Error "Missing required error details"
        return $false
    }

    return $true
}

function Test-RetryBehavior {
    <#
    .SYNOPSIS
        Tests if retry logic is correctly applied for retryable errors.
    .PARAMETER Response
        The API response object to test.
    .PARAMETER ExpectedRetries
        The expected number of retry attempts.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [ValidateRange(0, 5)]
        [int]$ExpectedRetries
    )

    # Check if error is retryable
    $retryableStatusCodes = @($HTTP_ERROR_CODES.RATE_LIMIT, $HTTP_ERROR_CODES.SERVER_ERROR, $HTTP_ERROR_CODES.SERVICE_UNAVAILABLE)
    $isRetryable = $Response.StatusCode -in $retryableStatusCodes

    if (-not $isRetryable -and $ExpectedRetries -gt 0) {
        Write-Error "Non-retryable error status code: $($Response.StatusCode)"
        return $false
    }

    # Validate retry headers for rate limit responses
    if ($Response.StatusCode -eq $HTTP_ERROR_CODES.RATE_LIMIT) {
        if (-not $Response.Headers.ContainsKey('Retry-After')) {
            Write-Error "Missing Retry-After header for rate limit response"
            return $false
        }

        if (-not [int]::TryParse($Response.Headers['Retry-After'], [ref]$null)) {
            Write-Error "Invalid Retry-After value: $($Response.Headers['Retry-After'])"
            return $false
        }
    }

    # Validate retry details in error object
    if ($isRetryable) {
        if (-not $Response.error.retryable) {
            Write-Error "Retryable error not marked as retryable in response"
            return $false
        }
    }

    return $true
}

function Test-ErrorCategory {
    <#
    .SYNOPSIS
        Tests if HTTP status codes are mapped to correct PowerShell error categories.
    .PARAMETER StatusCode
        The HTTP status code to test.
    .PARAMETER ExpectedCategory
        The expected PowerShell error category.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(400, 599)]
        [int]$StatusCode,

        [Parameter(Mandatory)]
        [ValidateSet('InvalidArgument', 'SecurityError', 'PermissionDenied', 
                    'ObjectNotFound', 'LimitsExceeded', 'InvalidOperation', 'ConnectionError')]
        [string]$ExpectedCategory
    )

    # Validate status code is mapped
    if (-not $ERROR_CATEGORIES.ContainsKey($StatusCode.ToString())) {
        Write-Error "No category mapping for status code: $StatusCode"
        return $false
    }

    # Check category mapping
    $actualCategory = $ERROR_CATEGORIES[$StatusCode.ToString()]
    if ($actualCategory -ne $ExpectedCategory) {
        Write-Error "Category mapping mismatch. Expected: $ExpectedCategory, Got: $actualCategory"
        return $false
    }

    # Validate terminating vs non-terminating behavior
    $isTerminating = $ExpectedCategory -in @('SecurityError', 'PermissionDenied', 'InvalidOperation')
    $errorTemplate = $script:ErrorResponses.errorResponseTemplate

    # Create test error response
    $errorResponse = New-MockErrorResponse -StatusCode $StatusCode `
                                         -ErrorMessage "Test error message" `
                                         -PSErrorCategory $ExpectedCategory

    # Validate error response matches expected behavior
    if ($isTerminating -and -not $errorResponse.error.powerShell.isTerminating) {
        Write-Error "Error should be terminating for category: $ExpectedCategory"
        return $false
    }

    return $true
}

function Test-SecurityError {
    <#
    .SYNOPSIS
        Tests handling of security-related errors.
    .PARAMETER Response
        The API response object to test.
    .PARAMETER ErrorType
        The type of security error (Authentication/Authorization).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [ValidateSet('Authentication', 'Authorization')]
        [string]$ErrorType
    )

    # Validate security error status codes
    $expectedCode = switch ($ErrorType) {
        'Authentication' { $HTTP_ERROR_CODES.UNAUTHORIZED }
        'Authorization' { $HTTP_ERROR_CODES.FORBIDDEN }
    }

    if ($Response.StatusCode -ne $expectedCode) {
        Write-Error "Invalid status code for $ErrorType error. Expected: $expectedCode, Got: $($Response.StatusCode)"
        return $false
    }

    # Validate security-specific headers
    $requiredHeaders = @('X-Error-Source', 'Request-Id')
    foreach ($header in $requiredHeaders) {
        if (-not $Response.Headers.ContainsKey($header)) {
            Write-Error "Missing security header: $header"
            return $false
        }
    }

    # Validate error category
    $expectedCategory = switch ($ErrorType) {
        'Authentication' { 'SecurityError' }
        'Authorization' { 'PermissionDenied' }
    }

    if ($Response.error.powerShell.errorCategory -ne $expectedCategory) {
        Write-Error "Invalid error category. Expected: $expectedCategory, Got: $($Response.error.powerShell.errorCategory)"
        return $false
    }

    # Validate security error details
    if (-not $Response.error.details) {
        Write-Error "Missing security error details"
        return $false
    }

    # Validate error is marked as terminating
    if (-not $Response.error.powerShell.isTerminating) {
        Write-Error "Security errors must be terminating"
        return $false
    }

    return $true
}

# Export test functions
Export-ModuleMember -Function @(
    'Test-ErrorResponse',
    'Test-RetryBehavior',
    'Test-ErrorCategory',
    'Test-SecurityError'
)