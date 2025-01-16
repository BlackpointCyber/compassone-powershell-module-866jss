using module Microsoft.PowerShell.Utility # Version 5.1.0+

# Global configuration defaults
$script:MockHttpClientConfig = @{
    DefaultTimeout = 30
    MaxRetries = 3
    SimulateLatency = $false
    LatencyMs = 100
    EnableRequestLogging = $true
    MaxHistorySize = 1000
    ValidateResponses = $true
    ErrorSimulation = @{
        EnableRandomErrors = $false
        ErrorRate = 0.1
        ErrorTypes = @('400', '401', '403', '404', '429', '500', '503')
    }
}

# Import mock response templates
$script:ApiResponses = Get-Content -Path "$PSScriptRoot/ApiResponses.json" | ConvertFrom-Json

class MockHttpClient {
    [hashtable]$ResponseQueue
    [hashtable]$Configuration
    [System.Collections.ArrayList]$RequestHistory
    [object]$ErrorSimulation
    [hashtable]$ResponseValidation
    [object]$LatencySimulation

    MockHttpClient([hashtable]$Configuration) {
        $this.ResponseQueue = @{}
        $this.Configuration = $Configuration
        $this.RequestHistory = [System.Collections.ArrayList]::new()
        $this.ErrorSimulation = $Configuration.ErrorSimulation
        $this.ResponseValidation = @{
            ValidateSchema = $Configuration.ValidateResponses
            Templates = $script:ApiResponses.responseTemplates
        }
        $this.LatencySimulation = @{
            Enabled = $Configuration.SimulateLatency
            LatencyMs = $Configuration.LatencyMs
        }
    }

    [object] SendRequest([object]$Request) {
        # Record request start time
        $startTime = Get-Date

        # Validate request
        $this.ValidateRequest($Request)

        # Add request to history
        if ($this.Configuration.EnableRequestLogging) {
            $requestEntry = @{
                Method = $Request.Method
                Uri = $Request.Uri
                Headers = $Request.Headers
                Body = $Request.Body
                Timestamp = $startTime
            }
            $null = $this.RequestHistory.Add($requestEntry)

            # Trim history if needed
            if ($this.RequestHistory.Count -gt $this.Configuration.MaxHistorySize) {
                $this.RequestHistory.RemoveRange(0, $this.RequestHistory.Count - $this.Configuration.MaxHistorySize)
            }
        }

        # Check for error simulation
        if ($this.ErrorSimulation.EnableRandomErrors) {
            $random = Get-Random -Minimum 0 -Maximum 1
            if ($random -lt $this.ErrorSimulation.ErrorRate) {
                $errorType = Get-Random -InputObject $this.ErrorSimulation.ErrorTypes
                return $this.GenerateErrorResponse($errorType)
            }
        }

        # Find matching response
        $response = $this.FindMatchingResponse($Request)
        if (-not $response) {
            return $this.GenerateErrorResponse('404')
        }

        # Apply latency simulation
        if ($this.LatencySimulation.Enabled) {
            Start-Sleep -Milliseconds $this.LatencySimulation.LatencyMs
        }

        # Add timing information
        $endTime = Get-Date
        $response | Add-Member -MemberType NoteProperty -Name 'RequestDuration' -Value ($endTime - $startTime)

        return $response
    }

    [array] GetRequestHistory([hashtable]$Filter) {
        $filteredHistory = $this.RequestHistory

        if ($Filter) {
            if ($Filter.Method) {
                $filteredHistory = $filteredHistory | Where-Object { $_.Method -eq $Filter.Method }
            }
            if ($Filter.Uri) {
                $filteredHistory = $filteredHistory | Where-Object { $_.Uri -like $Filter.Uri }
            }
            if ($Filter.StartTime) {
                $filteredHistory = $filteredHistory | Where-Object { $_.Timestamp -ge $Filter.StartTime }
            }
            if ($Filter.EndTime) {
                $filteredHistory = $filteredHistory | Where-Object { $_.Timestamp -le $Filter.EndTime }
            }
        }

        return $filteredHistory
    }

    hidden [void] ValidateRequest($Request) {
        if (-not $Request.Method) {
            throw [System.ArgumentException]::new('Request method is required')
        }
        if (-not $Request.Uri) {
            throw [System.ArgumentException]::new('Request URI is required')
        }
    }

    hidden [object] FindMatchingResponse($Request) {
        $key = "$($Request.Method):$($Request.Uri)"
        return $this.ResponseQueue[$key]
    }

    hidden [object] GenerateErrorResponse($StatusCode) {
        $errorTemplate = $script:ApiResponses.errorResponses | Where-Object { $_.statusCode -eq $StatusCode }
        if (-not $errorTemplate) {
            $errorTemplate = $script:ApiResponses.responseTemplates.baseErrorResponse
            $errorTemplate.statusCode = $StatusCode
        }
        return $errorTemplate
    }
}

function New-MockHttpClient {
    [CmdletBinding()]
    param (
        [Parameter()]
        [hashtable]$Configuration = @{}
    )

    # Merge provided configuration with defaults
    $finalConfig = $script:MockHttpClientConfig.Clone()
    foreach ($key in $Configuration.Keys) {
        $finalConfig[$key] = $Configuration[$key]
    }

    return [MockHttpClient]::new($finalConfig)
}

function Add-MockResponse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Method,
        
        [Parameter(Mandatory)]
        [string]$Uri,
        
        [Parameter(Mandatory)]
        [object]$Response,
        
        [Parameter()]
        [hashtable]$MatchingRules = @{}
    )

    $key = "$Method:$Uri"
    
    # Validate response against templates
    if ($script:MockHttpClientConfig.ValidateResponses) {
        if ($Response.statusCode -ge 400) {
            $template = $script:ApiResponses.responseTemplates.baseErrorResponse
        } else {
            $template = $script:ApiResponses.responseTemplates.baseSuccessResponse
        }
        
        # Ensure required properties exist
        foreach ($prop in $template.PSObject.Properties.Name) {
            if (-not $Response.PSObject.Properties[$prop]) {
                throw "Response missing required property: $prop"
            }
        }
    }

    $script:MockHttpClient.ResponseQueue[$key] = $Response
}

function Invoke-MockRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Method,
        
        [Parameter(Mandatory)]
        [string]$Uri,
        
        [Parameter()]
        [object]$Body,
        
        [Parameter()]
        [hashtable]$Headers = @{}
    )

    $request = @{
        Method = $Method
        Uri = $Uri
        Body = $Body
        Headers = $Headers
    }

    return $script:MockHttpClient.SendRequest($request)
}

function Clear-MockResponses {
    [CmdletBinding()]
    param()

    $script:MockHttpClient.ResponseQueue.Clear()
    $script:MockHttpClient.RequestHistory.Clear()
    $script:MockHttpClient.ErrorSimulation = $script:MockHttpClientConfig.ErrorSimulation.Clone()
    $script:MockHttpClient.LatencySimulation.Enabled = $script:MockHttpClientConfig.SimulateLatency
    $script:MockHttpClient.LatencySimulation.LatencyMs = $script:MockHttpClientConfig.LatencyMs
}

# Initialize global mock client instance
$script:MockHttpClient = New-MockHttpClient

Export-ModuleMember -Function @(
    'New-MockHttpClient',
    'Add-MockResponse',
    'Invoke-MockRequest',
    'Clear-MockResponses'
)