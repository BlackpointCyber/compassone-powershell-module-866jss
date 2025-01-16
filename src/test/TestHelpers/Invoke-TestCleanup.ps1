#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.6' }

<#
.SYNOPSIS
    Performs comprehensive cleanup of test environment resources with cross-platform support.
.DESCRIPTION
    Provides thorough cleanup of test artifacts, temporary files, mock data, and environment
    state with parallel execution safety and platform-specific handling.
.PARAMETER TestPath
    Base path for test cleanup operations. Defaults to test module location if not specified.
.PARAMETER RemoveCredentials
    Switch to remove test credentials from SecretStore.
.PARAMETER Force
    Switch to force cleanup operations without confirmation.
.PARAMETER RetryAttempts
    Number of retry attempts for cleanup operations. Default: 3
.PARAMETER RetryDelaySeconds
    Delay in seconds between retry attempts. Default: 5
#>

# Module-level variables
$script:TestModulePath = "$PSScriptRoot/../../PSCompassOne"
$script:TestConfigPath = "$PSScriptRoot/../TestConfig"
$script:TestDataPath = "$PSScriptRoot/../TestData"
$script:CleanupLockFile = Join-Path $env:TEMP "PSCompassOne_Cleanup.lock"
$script:CleanupLogFile = Join-Path $env:TEMP "PSCompassOne_Cleanup.log"

# Import test settings
$testSettings = Get-Content -Path "$TestConfigPath/test.settings.json" | ConvertFrom-Json

function Write-CleanupLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:CleanupLogFile -Value $logMessage
    
    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message }
        default { Write-Verbose $Message }
    }
}

function Get-CleanupLock {
    param(
        [int]$TimeoutSeconds = 60
    )
    
    $startTime = Get-Date
    while ((Get-Date) -lt $startTime.AddSeconds($TimeoutSeconds)) {
        try {
            $lockFile = [System.IO.File]::Open($script:CleanupLockFile, 'Create', 'ReadWrite', 'None')
            return $lockFile
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }
    throw "Could not acquire cleanup lock within $TimeoutSeconds seconds"
}

function Remove-TestCredentials {
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    try {
        $store = Get-SecretStore
        if (-not $store.IsOpen) {
            Write-CleanupLog "SecretStore is locked. Attempting to unlock..." -Level Warning
            Unlock-SecretStore
        }
        
        $testCredentials = Get-SecretInfo | Where-Object { $_.Name -like "PSCompassOne_Test_*" }
        foreach ($cred in $testCredentials) {
            Remove-Secret -Name $cred.Name -Force:$Force
            Write-CleanupLog "Removed test credential: $($cred.Name)"
        }
        
        return $true
    }
    catch {
        Write-CleanupLog "Failed to remove test credentials: $_" -Level Error
        return $false
    }
}

function Clear-TestDirectories {
    [CmdletBinding()]
    param(
        [string]$BasePath,
        [switch]$Force,
        [int]$RetryAttempts = 3
    )
    
    try {
        $paths = @(
            (Join-Path $BasePath $testSettings.TestEnvironment.TempPath),
            (Join-Path $BasePath $testSettings.TestEnvironment.OutputPath),
            (Join-Path $BasePath $testSettings.TestEnvironment.TestDataPath),
            (Join-Path $BasePath $testSettings.TestEnvironment.MockDataPath)
        )
        
        foreach ($path in $paths) {
            if (Test-Path $path) {
                $attempt = 0
                $success = $false
                
                while (-not $success -and $attempt -lt $RetryAttempts) {
                    try {
                        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                            # Windows-specific handling
                            attrib -R $path /S /D
                            Remove-Item -Path $path -Recurse -Force:$Force -ErrorAction Stop
                        }
                        else {
                            # Unix-like systems
                            chmod -R +w $path 2>$null
                            Remove-Item -Path $path -Recurse -Force:$Force -ErrorAction Stop
                        }
                        $success = $true
                    }
                    catch {
                        $attempt++
                        if ($attempt -lt $RetryAttempts) {
                            Start-Sleep -Seconds 2
                        }
                        else {
                            Write-CleanupLog "Failed to remove directory $path after $RetryAttempts attempts: $_" -Level Error
                            return $false
                        }
                    }
                }
                Write-CleanupLog "Removed directory: $path"
            }
        }
        return $true
    }
    catch {
        Write-CleanupLog "Error clearing test directories: $_" -Level Error
        return $false
    }
}

function Invoke-TestCleanup {
    [CmdletBinding()]
    param(
        [string]$TestPath = $script:TestModulePath,
        [switch]$RemoveCredentials,
        [switch]$Force,
        [int]$RetryAttempts = 3,
        [int]$RetryDelaySeconds = 5
    )
    
    $cleanupSuccess = $true
    $lockFile = $null
    
    try {
        Write-CleanupLog "Starting test environment cleanup..."
        
        # Acquire cleanup lock
        $lockFile = Get-CleanupLock
        Write-CleanupLog "Acquired cleanup lock"
        
        # Clear test directories
        if (-not (Clear-TestDirectories -BasePath $TestPath -Force:$Force -RetryAttempts $RetryAttempts)) {
            $cleanupSuccess = $false
        }
        
        # Remove test credentials if specified
        if ($RemoveCredentials) {
            if (-not (Remove-TestCredentials -Force:$Force)) {
                $cleanupSuccess = $false
            }
        }
        
        # Reset environment variables
        $testEnvVars = Get-ChildItem env: | Where-Object { $_.Name -like "PSCompassOne_Test_*" }
        foreach ($var in $testEnvVars) {
            Remove-Item env:$($var.Name) -ErrorAction SilentlyContinue
            Write-CleanupLog "Removed environment variable: $($var.Name)"
        }
        
        # Clean old log files
        $logRetentionDays = $testSettings.Logging.RetentionDays
        Get-ChildItem -Path (Split-Path $script:CleanupLogFile) -Filter "PSCompassOne_*.log" |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$logRetentionDays) } |
            Remove-Item -Force:$Force
        
        if ($cleanupSuccess) {
            Write-CleanupLog "Test environment cleanup completed successfully"
        }
        else {
            Write-CleanupLog "Test environment cleanup completed with some failures" -Level Warning
        }
        
        return $cleanupSuccess
    }
    catch {
        Write-CleanupLog "Critical error during test cleanup: $_" -Level Error
        return $false
    }
    finally {
        if ($lockFile) {
            $lockFile.Close()
            $lockFile.Dispose()
            Remove-Item -Path $script:CleanupLockFile -Force -ErrorAction SilentlyContinue
            Write-CleanupLog "Released cleanup lock"
        }
    }
}

# Export the main cleanup function
Export-ModuleMember -Function Invoke-TestCleanup