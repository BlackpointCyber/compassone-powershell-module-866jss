#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

# Import required test dependencies
. "$PSScriptRoot/Initialize-TestEnvironment.ps1"
$mockCredentials = Get-Content "$PSScriptRoot/../Mocks/TestCredentials.json" | ConvertFrom-Json

# Global test configuration
$script:TEST_API_URL = 'https://api.test.compassone.com'
$script:TEST_VAULT_NAME = 'PSCompassOneTest'
$script:MAX_RETRY_ATTEMPTS = 3
$script:DEFAULT_TIMEOUT_SECONDS = 30
$script:SECURITY_LOG_PATH = "$env:TEMP/PSCompassOne/security.log"

function Test-ValidAuthentication {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory)]
        [string]
        $ApiUrl,

        [Parameter()]
        [int]
        $TimeoutSeconds = $script:DEFAULT_TIMEOUT_SECONDS,

        [Parameter()]
        [int]
        $RetryAttempts = $script:MAX_RETRY_ATTEMPTS
    )

    try {
        # Initialize test environment with valid credentials
        $testEnv = Initialize-TestEnvironment -ModulePath "$PSScriptRoot/../../PSCompassOne" -TestPath $PSScriptRoot

        # Configure retry policy
        $retryCount = 0
        $success = $false

        while (-not $success -and $retryCount -lt $RetryAttempts) {
            try {
                # Attempt authentication
                $authResult = Invoke-MockRequest -Method 'POST' -Uri "$ApiUrl/auth" -Body @{
                    apiKey = $Credential.GetNetworkCredential().Password
                }

                # Validate token format and expiration
                if ($authResult.statusCode -eq 200 -and 
                    $authResult.body.token -match $mockCredentials.validCredentials.validationPattern) {
                    
                    # Store token securely
                    $secureToken = ConvertTo-SecureString -String $authResult.body.token -AsPlainText -Force
                    Set-Secret -Name "PSCompassOne_Token" -SecureValue $secureToken -Vault $script:TEST_VAULT_NAME

                    # Log successful authentication
                    $logEntry = @{
                        Timestamp = Get-Date -Format 'o'
                        Event = 'Authentication'
                        Status = 'Success'
                        ApiUrl = $ApiUrl
                        RequestId = $authResult.headers.'Request-Id'
                    } | ConvertTo-Json
                    Add-Content -Path $script:SECURITY_LOG_PATH -Value $logEntry

                    $success = $true
                }
            }
            catch {
                $retryCount++
                if ($retryCount -lt $RetryAttempts) {
                    Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))
                }
            }
        }

        return $success
    }
    catch {
        Write-Error "Authentication test failed: $_"
        return $false
    }
    finally {
        # Cleanup test artifacts
        Remove-Secret -Name "PSCompassOne_Token" -Vault $script:TEST_VAULT_NAME -ErrorAction SilentlyContinue
    }
}

function Test-InvalidAuthentication {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory)]
        [string]
        $ApiUrl,

        [Parameter()]
        [string[]]
        $ExpectedErrorTypes = @('Invalid credentials', 'Authentication failed', 'Unauthorized access')
    )

    try {
        # Initialize test environment
        $testEnv = Initialize-TestEnvironment -ModulePath "$PSScriptRoot/../../PSCompassOne" -TestPath $PSScriptRoot

        # Attempt authentication with invalid credentials
        $authResult = Invoke-MockRequest -Method 'POST' -Uri "$ApiUrl/auth" -Body @{
            apiKey = $Credential.GetNetworkCredential().Password
        }

        # Validate error response
        $validError = $false
        if ($authResult.statusCode -eq 401) {
            $errorMessage = $authResult.error.message
            $validError = $ExpectedErrorTypes | Where-Object { $errorMessage -match $_ }

            # Log authentication failure
            $logEntry = @{
                Timestamp = Get-Date -Format 'o'
                Event = 'Authentication'
                Status = 'Failure'
                ApiUrl = $ApiUrl
                ErrorType = $authResult.error.code
                RequestId = $authResult.headers.'Request-Id'
            } | ConvertTo-Json
            Add-Content -Path $script:SECURITY_LOG_PATH -Value $logEntry
        }

        # Verify no token was stored
        $storedToken = Get-Secret -Name "PSCompassOne_Token" -Vault $script:TEST_VAULT_NAME -ErrorAction SilentlyContinue
        if ($storedToken) {
            throw "Security violation: Token should not be stored for failed authentication"
        }

        return $validError
    }
    catch {
        Write-Error "Invalid authentication test failed: $_"
        return $false
    }
}

function Test-ExpiredAuthentication {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory)]
        [string]
        $ApiUrl,

        [Parameter()]
        [int]
        $ExpirationSeconds = 1
    )

    try {
        # Initialize test environment
        $testEnv = Initialize-TestEnvironment -ModulePath "$PSScriptRoot/../../PSCompassOne" -TestPath $PSScriptRoot

        # Get initial token
        $authResult = Invoke-MockRequest -Method 'POST' -Uri "$ApiUrl/auth" -Body @{
            apiKey = $Credential.GetNetworkCredential().Password
        }

        if ($authResult.statusCode -ne 200) {
            throw "Initial authentication failed"
        }

        # Wait for token expiration
        Start-Sleep -Seconds $ExpirationSeconds

        # Attempt API call with expired token
        $apiResult = Invoke-MockRequest -Method 'GET' -Uri "$ApiUrl/test" -Headers @{
            'Authorization' = "Bearer $($authResult.body.token)"
        }

        # Validate token refresh behavior
        $validRefresh = $false
        if ($apiResult.statusCode -eq 401 -and 
            $apiResult.error.message -match $mockCredentials.expiredCredentials.refreshPattern) {
            
            # Attempt token refresh
            $refreshResult = Invoke-MockRequest -Method 'POST' -Uri "$ApiUrl/auth/refresh" -Body @{
                token = $authResult.body.token
            }

            if ($refreshResult.statusCode -eq 200) {
                # Store refreshed token
                $secureToken = ConvertTo-SecureString -String $refreshResult.body.token -AsPlainText -Force
                Set-Secret -Name "PSCompassOne_Token" -SecureValue $secureToken -Vault $script:TEST_VAULT_NAME

                # Log token refresh
                $logEntry = @{
                    Timestamp = Get-Date -Format 'o'
                    Event = 'TokenRefresh'
                    Status = 'Success'
                    ApiUrl = $ApiUrl
                    RequestId = $refreshResult.headers.'Request-Id'
                } | ConvertTo-Json
                Add-Content -Path $script:SECURITY_LOG_PATH -Value $logEntry

                $validRefresh = $true
            }
        }

        return $validRefresh
    }
    catch {
        Write-Error "Expired authentication test failed: $_"
        return $false
    }
    finally {
        # Cleanup test artifacts
        Remove-Secret -Name "PSCompassOne_Token" -Vault $script:TEST_VAULT_NAME -ErrorAction SilentlyContinue
    }
}

function Test-SecretStoreIntegration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [PSCredential]
        $Credential,

        [Parameter()]
        [string]
        $VaultName = $script:TEST_VAULT_NAME,

        [Parameter()]
        [ValidateSet('Windows', 'Linux', 'MacOS')]
        [string]
        $Platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
    )

    try {
        # Initialize SecretStore vault
        $null = Initialize-SecretStore -Scope CurrentUser -Password (
            ConvertTo-SecureString -String "TestPassword123!" -AsPlainText -Force
        )

        # Test credential storage
        $secureCredentials = @{
            ApiKey = $Credential.GetNetworkCredential().Password
            Platform = $Platform
            Timestamp = (Get-Date).ToString('o')
        } | ConvertTo-Json | ConvertTo-SecureString -AsPlainText -Force

        Set-Secret -Name "PSCompassOne_Credentials_$Platform" -SecureValue $secureCredentials -Vault $VaultName

        # Verify credential retrieval
        $storedCredentials = Get-Secret -Name "PSCompassOne_Credentials_$Platform" -Vault $VaultName
        $credentialJson = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($storedCredentials)
        )
        $credentialObject = $credentialJson | ConvertFrom-Json

        # Validate stored credentials
        $valid = $credentialObject.ApiKey -eq $Credential.GetNetworkCredential().Password -and
                $credentialObject.Platform -eq $Platform

        # Log vault operations
        $logEntry = @{
            Timestamp = Get-Date -Format 'o'
            Event = 'SecretStore'
            Status = if ($valid) { 'Success' } else { 'Failure' }
            Platform = $Platform
            VaultName = $VaultName
        } | ConvertTo-Json
        Add-Content -Path $script:SECURITY_LOG_PATH -Value $logEntry

        return $valid
    }
    catch {
        Write-Error "SecretStore integration test failed: $_"
        return $false
    }
    finally {
        # Cleanup vault
        Remove-Secret -Name "PSCompassOne_Credentials_$Platform" -Vault $VaultName -ErrorAction SilentlyContinue
    }
}

# Export test functions
Export-ModuleMember -Function @(
    'Test-ValidAuthentication',
    'Test-InvalidAuthentication',
    'Test-ExpiredAuthentication',
    'Test-SecretStoreIntegration'
)