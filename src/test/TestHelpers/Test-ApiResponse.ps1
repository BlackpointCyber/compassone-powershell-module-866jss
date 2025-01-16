using module Microsoft.PowerShell.Utility # Version 5.1.0+
using module Pester # Version 5.3.0+

# Import required test data and assertions
$script:ApiResponses = Get-Content -Path "$PSScriptRoot/../Mocks/ApiResponses.json" | ConvertFrom-Json

# Global validation constants
$script:ValidStatusCodes = @(200, 201, 202, 204, 400, 401, 403, 404, 429, 500, 503)
$script:ValidContentTypes = @('application/json')

function Test-ApiResponseStatus {
    <#
    .SYNOPSIS
        Validates if the API response has a valid HTTP status code.
    .DESCRIPTION
        Performs comprehensive validation of API response status codes against expected values
        with detailed error reporting for test diagnostics.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [int]$ExpectedStatus
    )

    # Validate response object
    if (-not $Response) {
        Should -Fail -Because "Response object is null"
        return $false
    }

    # Extract status code
    $actualStatus = $Response.statusCode
    if (-not $actualStatus) {
        Should -Fail -Because "Response does not contain a status code"
        return $false
    }

    # Validate status code is in allowed list
    if ($actualStatus -notin $script:ValidStatusCodes) {
        Should -Fail -Because "Status code $actualStatus is not in the list of valid status codes: $($script:ValidStatusCodes -join ', ')"
        return $false
    }

    # Compare with expected status
    if ($actualStatus -ne $ExpectedStatus) {
        $context = "Expected status code $ExpectedStatus but got $actualStatus"
        if ($Response.error) {
            $context += "`nError details: $($Response.error | ConvertTo-Json -Depth 3)"
        }
        Should -Be -ExpectedValue $ExpectedStatus -ActualValue $actualStatus -Because $context
        return $false
    }

    return $true
}

function Test-ApiResponseHeaders {
    <#
    .SYNOPSIS
        Validates API response headers against expected values.
    .DESCRIPTION
        Performs detailed validation of API response headers including required headers,
        content types, and custom header requirements.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [hashtable]$ExpectedHeaders
    )

    # Validate response headers exist
    if (-not $Response.headers) {
        Should -Fail -Because "Response does not contain headers"
        return $false
    }

    # Validate Content-Type
    $contentType = $Response.headers.'Content-Type'
    if (-not $contentType) {
        Should -Fail -Because "Response missing Content-Type header"
        return $false
    }
    if ($contentType -notin $script:ValidContentTypes) {
        Should -Fail -Because "Invalid Content-Type: $contentType. Expected one of: $($script:ValidContentTypes -join ', ')"
        return $false
    }

    # Validate Request-Id
    $requestId = $Response.headers.'Request-Id'
    if (-not $requestId) {
        Should -Fail -Because "Response missing Request-Id header"
        return $false
    }
    if ($requestId -notmatch '^req-[a-zA-Z0-9-]+$') {
        Should -Fail -Because "Invalid Request-Id format: $requestId"
        return $false
    }

    # Compare expected headers
    foreach ($header in $ExpectedHeaders.Keys) {
        $expectedValue = $ExpectedHeaders[$header]
        $actualValue = $Response.headers[$header]

        if (-not $actualValue) {
            Should -Fail -Because "Missing expected header: $header"
            return $false
        }

        if ($actualValue -ne $expectedValue) {
            Should -Be -ExpectedValue $expectedValue -ActualValue $actualValue -Because "Header value mismatch for $header"
            return $false
        }
    }

    return $true
}

function Test-ApiResponseBody {
    <#
    .SYNOPSIS
        Validates API response body structure against expected template.
    .DESCRIPTION
        Performs deep validation of API response body including schema validation,
        required properties, and nested object structures.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [object]$ExpectedTemplate
    )

    # Validate response has a body
    if (-not $Response.body) {
        Should -Fail -Because "Response does not contain a body"
        return $false
    }

    # Parse response body if it's a string
    $responseBody = $Response.body
    if ($responseBody -is [string]) {
        try {
            $responseBody = $responseBody | ConvertFrom-Json
        }
        catch {
            Should -Fail -Because "Failed to parse response body as JSON: $_"
            return $false
        }
    }

    # Validate required properties exist
    foreach ($prop in $ExpectedTemplate.PSObject.Properties) {
        if (-not $responseBody.PSObject.Properties[$prop.Name]) {
            Should -Fail -Because "Response body missing required property: $($prop.Name)"
            return $false
        }

        # Validate property type matches
        $expectedType = $prop.Value.GetType()
        $actualType = $responseBody.($prop.Name).GetType()
        if ($actualType -ne $expectedType) {
            Should -Fail -Because "Property type mismatch for $($prop.Name). Expected: $expectedType, Actual: $actualType"
            return $false
        }
    }

    # Validate metadata if present
    if ($responseBody.metadata) {
        if (-not $responseBody.metadata.formatType) {
            Should -Fail -Because "Response metadata missing formatType"
            return $false
        }
        if (-not $responseBody.metadata.typeNames) {
            Should -Fail -Because "Response metadata missing typeNames"
            return $false
        }
    }

    return $true
}

function Test-ApiErrorResponse {
    <#
    .SYNOPSIS
        Validates API error response structure and content.
    .DESCRIPTION
        Performs comprehensive validation of API error responses including error codes,
        messages, and PowerShell error category mapping.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [string]$ExpectedErrorCode
    )

    # Validate error status code
    if ($Response.statusCode -lt 400) {
        Should -Fail -Because "Response status code $($Response.statusCode) is not an error code"
        return $false
    }

    # Validate error structure
    if (-not $Response.error) {
        Should -Fail -Because "Error response missing error object"
        return $false
    }

    $error = $Response.error

    # Validate required error properties
    if (-not $error.code) {
        Should -Fail -Because "Error missing error code"
        return $false
    }
    if (-not $error.message) {
        Should -Fail -Because "Error missing error message"
        return $false
    }
    if (-not $error.powerShell) {
        Should -Fail -Because "Error missing PowerShell error details"
        return $false
    }

    # Validate error code matches expected
    if ($error.code -ne $ExpectedErrorCode) {
        Should -Be -ExpectedValue $ExpectedErrorCode -ActualValue $error.code -Because "Error code mismatch"
        return $false
    }

    # Validate PowerShell error details
    $psError = $error.powerShell
    if (-not $psError.errorCategory) {
        Should -Fail -Because "PowerShell error missing errorCategory"
        return $false
    }
    if (-not $psError.errorId) {
        Should -Fail -Because "PowerShell error missing errorId"
        return $false
    }
    if (-not $psError.recommendedAction) {
        Should -Fail -Because "PowerShell error missing recommendedAction"
        return $false
    }

    return $true
}

function Test-ApiPaginatedResponse {
    <#
    .SYNOPSIS
        Validates API paginated response structure and content.
    .DESCRIPTION
        Performs comprehensive validation of paginated API responses including
        pagination metadata, navigation links, and item collections.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [int]$ExpectedPageSize,

        [Parameter(Mandatory)]
        [int]$ExpectedPage
    )

    # Validate response has items array
    if (-not $Response.body.items) {
        Should -Fail -Because "Paginated response missing items array"
        return $false
    }

    # Validate pagination metadata
    if (-not $Response.body.totalItems) {
        Should -Fail -Because "Paginated response missing totalItems"
        return $false
    }
    if (-not $Response.body.pageSize) {
        Should -Fail -Because "Paginated response missing pageSize"
        return $false
    }
    if (-not $Response.body.pageNumber) {
        Should -Fail -Because "Paginated response missing pageNumber"
        return $false
    }

    # Validate page size
    if ($Response.body.pageSize -ne $ExpectedPageSize) {
        Should -Be -ExpectedValue $ExpectedPageSize -ActualValue $Response.body.pageSize -Because "Page size mismatch"
        return $false
    }

    # Validate page number
    if ($Response.body.pageNumber -ne $ExpectedPage) {
        Should -Be -ExpectedValue $ExpectedPage -ActualValue $Response.body.pageNumber -Because "Page number mismatch"
        return $false
    }

    # Validate items count against page size
    if ($Response.body.items.Count -gt $ExpectedPageSize) {
        Should -Fail -Because "Items count ($($Response.body.items.Count)) exceeds page size ($ExpectedPageSize)"
        return $false
    }

    # Validate pagination metadata
    if ($Response.body.metadata.paginationInfo) {
        $pagination = $Response.body.metadata.paginationInfo
        if (-not $pagination.PSObject.Properties['hasNextPage']) {
            Should -Fail -Because "Pagination info missing hasNextPage"
            return $false
        }
        if (-not $pagination.PSObject.Properties['hasPreviousPage']) {
            Should -Fail -Because "Pagination info missing hasPreviousPage"
            return $false
        }
        if (-not $pagination.PSObject.Properties['totalPages']) {
            Should -Fail -Because "Pagination info missing totalPages"
            return $false
        }
    }

    return $true
}

# Export functions
Export-ModuleMember -Function @(
    'Test-ApiResponseStatus',
    'Test-ApiResponseHeaders',
    'Test-ApiResponseBody',
    'Test-ApiErrorResponse',
    'Test-ApiPaginatedResponse'
)