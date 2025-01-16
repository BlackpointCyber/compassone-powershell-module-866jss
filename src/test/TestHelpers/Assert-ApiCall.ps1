using module Microsoft.PowerShell.Utility # Version 5.1.0+
using module Pester # Version 5.3.0+

# Global configuration for assertion behavior
$script:AssertionConfig = @{
    StrictValidation = $true
    ValidateHeaders = $true
    ValidateParameters = $true
    ValidateBody = $true
    CaseInsensitiveHeaders = $true
    AllowPartialMatches = $false
    DetailedErrors = $true
    MaxHistorySize = 100
    TimeoutSeconds = 30
}

function Assert-ApiCallMade {
    <#
    .SYNOPSIS
        Asserts that a specific API call was made with the expected parameters.
    .DESCRIPTION
        Validates that an API call matching the specified criteria was made through the mock HTTP client,
        performing detailed validation of request components including method, URI, headers, and body.
    .PARAMETER MockHttpClient
        The mock HTTP client instance containing the request history.
    .PARAMETER ExpectedMethod
        The expected HTTP method (GET, POST, PUT, DELETE, etc.).
    .PARAMETER ExpectedUri
        The expected URI pattern to match against.
    .PARAMETER ExpectedHeaders
        Optional hashtable of expected request headers.
    .PARAMETER ExpectedBody
        Optional object representing the expected request body.
    .PARAMETER PartialMatch
        Switch to enable partial matching of request components.
    .PARAMETER CaseInsensitive
        Switch to enable case-insensitive matching.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MockHttpClient,

        [Parameter(Mandatory)]
        [string]$ExpectedMethod,

        [Parameter(Mandatory)]
        [string]$ExpectedUri,

        [Parameter()]
        [hashtable]$ExpectedHeaders,

        [Parameter()]
        [object]$ExpectedBody,

        [Parameter()]
        [switch]$PartialMatch,

        [Parameter()]
        [switch]$CaseInsensitive
    )

    # Validate input parameters
    if (-not $MockHttpClient) {
        throw [System.ArgumentNullException]::new('MockHttpClient')
    }

    # Get request history with timeout
    $startTime = Get-Date
    $history = $null
    while (-not $history -and ((Get-Date) - $startTime).TotalSeconds -lt $script:AssertionConfig.TimeoutSeconds) {
        $history = $MockHttpClient.GetRequestHistory()
        if (-not $history) {
            Start-Sleep -Milliseconds 100
        }
    }

    if (-not $history) {
        Should -Fail -Because "No API calls were recorded within timeout period of $($script:AssertionConfig.TimeoutSeconds) seconds"
        return
    }

    # Find matching request
    $matchingRequest = $history | Where-Object {
        $methodMatch = if ($CaseInsensitive) {
            $_.Method -eq $ExpectedMethod -or $_.Method -ieq $ExpectedMethod
        } else {
            $_.Method -eq $ExpectedMethod
        }

        $uriMatch = if ($PartialMatch) {
            $_.Uri -like "*$ExpectedUri*"
        } else {
            $_.Uri -eq $ExpectedUri
        }

        $methodMatch -and $uriMatch
    }

    if (-not $matchingRequest) {
        $message = "No matching API call found for Method: $ExpectedMethod, URI: $ExpectedUri`n"
        $message += "Recorded calls:`n"
        $history | ForEach-Object {
            $message += "- $($_.Method) $($_.Uri)`n"
        }
        Should -Fail -Because $message
        return
    }

    # Validate headers if specified
    if ($ExpectedHeaders -and $script:AssertionConfig.ValidateHeaders) {
        foreach ($header in $ExpectedHeaders.Keys) {
            $expectedValue = $ExpectedHeaders[$header]
            $actualValue = $matchingRequest.Headers[$header]

            if ($CaseInsensitive) {
                $headerMatch = $actualValue -ieq $expectedValue
            } else {
                $headerMatch = $actualValue -eq $expectedValue
            }

            if (-not $headerMatch) {
                Should -Fail -Because "Header mismatch for '$header'. Expected: '$expectedValue', Actual: '$actualValue'"
                return
            }
        }
    }

    # Validate body if specified
    if ($ExpectedBody -and $script:AssertionConfig.ValidateBody) {
        $expectedJson = $ExpectedBody | ConvertTo-Json -Depth 10
        $actualJson = $matchingRequest.Body | ConvertTo-Json -Depth 10

        if ($PartialMatch) {
            $bodyMatch = $actualJson -like "*$expectedJson*"
        } else {
            $bodyMatch = $actualJson -eq $expectedJson
        }

        if (-not $bodyMatch) {
            Should -Fail -Because "Body mismatch.`nExpected: $expectedJson`nActual: $actualJson"
            return
        }
    }

    # If we got here, all validations passed
    Should -BeTrue -Because "API call matched all criteria" -ActualValue $true
}

function Assert-ApiCallCount {
    <#
    .SYNOPSIS
        Asserts that the expected number of API calls were made.
    .DESCRIPTION
        Validates that the number of API calls matching the specified criteria matches the expected count.
    .PARAMETER MockHttpClient
        The mock HTTP client instance containing the request history.
    .PARAMETER ExpectedCount
        The expected number of matching API calls.
    .PARAMETER Method
        Optional HTTP method filter.
    .PARAMETER Uri
        Optional URI pattern filter.
    .PARAMETER Within
        Optional timespan to limit the search window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MockHttpClient,

        [Parameter(Mandatory)]
        [int]$ExpectedCount,

        [Parameter()]
        [string]$Method,

        [Parameter()]
        [string]$Uri,

        [Parameter()]
        [timespan]$Within
    )

    # Get request history
    $history = $MockHttpClient.GetRequestHistory()

    # Apply filters
    if ($Method) {
        $history = $history | Where-Object { $_.Method -eq $Method }
    }
    if ($Uri) {
        $history = $history | Where-Object { $_.Uri -like "*$Uri*" }
    }
    if ($Within) {
        $cutoffTime = (Get-Date) - $Within
        $history = $history | Where-Object { $_.Timestamp -ge $cutoffTime }
    }

    $actualCount = ($history | Measure-Object).Count

    if ($actualCount -ne $ExpectedCount) {
        $message = "Expected $ExpectedCount API call(s) but found $actualCount`n"
        if ($history) {
            $message += "Actual calls:`n"
            $history | ForEach-Object {
                $message += "- $($_.Method) $($_.Uri) at $($_.Timestamp)`n"
            }
        }
        Should -Be -ExpectedValue $ExpectedCount -ActualValue $actualCount -Because $message
    }
}

function Assert-ApiCallSequence {
    <#
    .SYNOPSIS
        Asserts that API calls were made in the expected sequence.
    .DESCRIPTION
        Validates that a sequence of API calls was made in the specified order with optional timing validation.
    .PARAMETER MockHttpClient
        The mock HTTP client instance containing the request history.
    .PARAMETER ExpectedCalls
        Array of expected call patterns in sequence.
    .PARAMETER WithinSequence
        Optional timespan for maximum duration of the sequence.
    .PARAMETER StrictOrder
        Switch to enforce strict ordering with no intervening calls.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MockHttpClient,

        [Parameter(Mandatory)]
        [array]$ExpectedCalls,

        [Parameter()]
        [timespan]$WithinSequence,

        [Parameter()]
        [switch]$StrictOrder
    )

    # Get request history
    $history = $MockHttpClient.GetRequestHistory()
    
    if (-not $history) {
        Should -Fail -Because "No API calls were recorded"
        return
    }

    $sequenceStart = $null
    $lastMatchIndex = -1
    $matchedCalls = @()

    # Validate each expected call in sequence
    foreach ($expectedCall in $ExpectedCalls) {
        $found = $false
        
        for ($i = $lastMatchIndex + 1; $i -lt $history.Count; $i++) {
            $request = $history[$i]
            
            # Skip if strict order and we found intervening calls
            if ($StrictOrder -and $i -ne $lastMatchIndex + 1 -and $lastMatchIndex -ne -1) {
                continue
            }

            if ($request.Method -eq $expectedCall.Method -and $request.Uri -like "*$($expectedCall.Uri)*") {
                if (-not $sequenceStart) {
                    $sequenceStart = $request.Timestamp
                }

                $found = $true
                $lastMatchIndex = $i
                $matchedCalls += $request
                break
            }
        }

        if (-not $found) {
            $message = "Missing expected API call in sequence: $($expectedCall.Method) $($expectedCall.Uri)`n"
            $message += "Actual sequence:`n"
            $history | ForEach-Object {
                $message += "- $($_.Method) $($_.Uri) at $($_.Timestamp)`n"
            }
            Should -Fail -Because $message
            return
        }
    }

    # Validate sequence timing if specified
    if ($WithinSequence -and $matchedCalls.Count -gt 0) {
        $sequenceDuration = $matchedCalls[-1].Timestamp - $sequenceStart
        if ($sequenceDuration -gt $WithinSequence) {
            Should -Fail -Because "Sequence duration ($sequenceDuration) exceeded maximum allowed time ($WithinSequence)"
            return
        }
    }
}

function Assert-NoApiCalls {
    <#
    .SYNOPSIS
        Asserts that no API calls were made matching the specified criteria.
    .DESCRIPTION
        Validates that no API calls matching the given method and URI patterns were made within the specified time window.
    .PARAMETER MockHttpClient
        The mock HTTP client instance containing the request history.
    .PARAMETER Method
        Optional HTTP method to match.
    .PARAMETER Uri
        Optional URI pattern to match.
    .PARAMETER Within
        Optional timespan to limit the search window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MockHttpClient,

        [Parameter()]
        [string]$Method,

        [Parameter()]
        [string]$Uri,

        [Parameter()]
        [timespan]$Within
    )

    # Get request history
    $history = $MockHttpClient.GetRequestHistory()

    # Apply filters
    if ($Method) {
        $history = $history | Where-Object { $_.Method -eq $Method }
    }
    if ($Uri) {
        $history = $history | Where-Object { $_.Uri -like "*$Uri*" }
    }
    if ($Within) {
        $cutoffTime = (Get-Date) - $Within
        $history = $history | Where-Object { $_.Timestamp -ge $cutoffTime }
    }

    if ($history) {
        $message = "Expected no matching API calls but found:`n"
        $history | ForEach-Object {
            $message += "- $($_.Method) $($_.Uri) at $($_.Timestamp)`n"
        }
        Should -Be -ExpectedValue 0 -ActualValue $history.Count -Because $message
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Assert-ApiCallMade',
    'Assert-ApiCallCount',
    'Assert-ApiCallSequence',
    'Assert-NoApiCalls'
)