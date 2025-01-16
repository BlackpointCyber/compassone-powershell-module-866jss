#Requires -Version 5.1
using namespace System.Net.Http
using module Microsoft.PowerShell.Utility

<#
.SYNOPSIS
    Creates mock HTTP responses for testing the PSCompassOne module.
.DESCRIPTION
    Provides helper functions to generate standardized mock HTTP responses with PowerShell-specific
    enhancements for testing API client functionality. Supports both success and error scenarios
    with proper status codes, headers, and PowerShell error categories.
#>

# HTTP Status Code Constants
Set-Variable -Name HTTP_SUCCESS_CODES -Value @(200, 201, 202, 204) -Option Constant
Set-Variable -Name HTTP_ERROR_CODES -Value @{
    BAD_REQUEST = 400
    UNAUTHORIZED = 401
    FORBIDDEN = 403
    NOT_FOUND = 404
    RATE_LIMIT = 429
    SERVER_ERROR = 500
    SERVICE_UNAVAILABLE = 503
} -Option Constant

# Response Constants
Set-Variable -Name RESPONSE_CONTENT_TYPE -Value 'application/json' -Option Constant
Set-Variable -Name ERROR_CATEGORY_MAP -Value @{
    '400' = 'InvalidArgument'
    '401' = 'SecurityError'
    '403' = 'PermissionDenied'
    '404' = 'ObjectNotFound'
    '429' = 'LimitsExceeded'
    '500' = 'InvalidOperation'
    '503' = 'ConnectionError'
} -Option Constant

function New-MockResponse {
    <#
    .SYNOPSIS
        Creates a new mock HTTP response object with PowerShell-specific enhancements.
    .PARAMETER StatusCode
        The HTTP status code for the response.
    .PARAMETER Body
        The response body object or string.
    .PARAMETER Headers
        Additional headers to include in the response.
    .PARAMETER PSFormatting
        PowerShell-specific formatting metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(200, 599)]
        [int]$StatusCode,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [hashtable]$PSFormatting = @{}
    )

    # Initialize default headers
    $defaultHeaders = @{
        'Content-Type' = RESPONSE_CONTENT_TYPE
        'Request-Id' = [guid]::NewGuid().ToString()
        'API-Version' = 'v1'
    }

    # Merge custom headers with defaults
    $responseHeaders = $defaultHeaders + $Headers

    # Convert body to JSON if it's an object
    if ($Body -is [object] -and $Body -isnot [string]) {
        $Body = $Body | ConvertTo-Json -Depth 10
    }

    # Create base response object
    $response = @{
        StatusCode = $StatusCode
        Headers = $responseHeaders
        Body = $Body
    }

    # Add PowerShell error category for error responses
    if ($StatusCode -ge 400) {
        $response.ErrorCategory = $ERROR_CATEGORY_MAP[$StatusCode.ToString()]
    }

    # Add PowerShell formatting metadata if provided
    if ($PSFormatting.Count -gt 0) {
        $response.PSFormatting = $PSFormatting
    }

    return [PSCustomObject]$response
}

function New-MockSuccessResponse {
    <#
    .SYNOPSIS
        Creates a success mock response with PowerShell formatting support.
    .PARAMETER Body
        The success response body.
    .PARAMETER StatusCode
        Optional status code (defaults to 200).
    .PARAMETER PSFormatting
        PowerShell-specific formatting metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Body,

        [Parameter()]
        [ValidateScript({$_ -in $HTTP_SUCCESS_CODES})]
        [int]$StatusCode = 200,

        [Parameter()]
        [hashtable]$PSFormatting = @{}
    )

    # Default PowerShell formatting if not provided
    if (-not $PSFormatting.ContainsKey('formatType')) {
        $PSFormatting.formatType = 'Default'
    }
    if (-not $PSFormatting.ContainsKey('defaultView')) {
        $PSFormatting.defaultView = 'Table'
    }

    # Create success response with formatting
    $response = New-MockResponse -StatusCode $StatusCode -Body $Body -PSFormatting $PSFormatting

    # Add success-specific headers
    $response.Headers['PowerShell-Format-Version'] = '1.0.0'

    return $response
}

function New-MockErrorResponse {
    <#
    .SYNOPSIS
        Creates an error mock response with PowerShell error category mapping.
    .PARAMETER StatusCode
        The HTTP error status code.
    .PARAMETER ErrorMessage
        The error message.
    .PARAMETER ErrorDetails
        Additional error details.
    .PARAMETER PSErrorCategory
        Optional PowerShell error category override.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({$_ -ge 400})]
        [int]$StatusCode,

        [Parameter(Mandatory)]
        [string]$ErrorMessage,

        [Parameter()]
        [object]$ErrorDetails = $null,

        [Parameter()]
        [string]$PSErrorCategory = $ERROR_CATEGORY_MAP[$StatusCode.ToString()]
    )

    # Get error template based on status code
    $errorTemplate = Get-Content -Path "$PSScriptRoot/../Mocks/ErrorResponses.json" | ConvertFrom-Json
    $template = $errorTemplate.errorResponseTemplate

    # Populate error response
    $errorBody = @{
        code = $template.error.code
        message = $ErrorMessage
        details = $ErrorDetails ?? $template.error.details
        powerShell = @{
            errorCategory = $PSErrorCategory
            errorId = "PSCompassOne.$($template.error.code)"
            recommendedAction = $template.error.recommendedAction
            troubleshooting = $template.error.troubleshooting
        }
    }

    # Add retry headers for rate limit errors
    $headers = @{}
    if ($StatusCode -eq $HTTP_ERROR_CODES.RATE_LIMIT) {
        $headers['Retry-After'] = '60'
    }

    return New-MockResponse -StatusCode $StatusCode -Body $errorBody -Headers $headers
}

# Export functions
Export-ModuleMember -Function @(
    'New-MockResponse',
    'New-MockSuccessResponse', 
    'New-MockErrorResponse'
)