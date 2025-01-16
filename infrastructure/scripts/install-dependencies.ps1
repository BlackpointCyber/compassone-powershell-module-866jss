#Requires -Version 5.1
#Requires -Modules @{ ModuleName='PowerShellGet'; ModuleVersion='2.2.5' }
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.Security'; ModuleVersion='7.0.0' }

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Parallel,
    [switch]$NoProgress
)

# Script constants
$script:ScriptRoot = $PSScriptRoot
$script:RequiredPSVersion = '5.1'
$script:MaxInstallRetries = 3
$script:ParallelJobLimit = 5
$script:SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Import build configuration
$buildConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '..\config\build.settings.json'
$buildConfig = Get-Content -Path $buildConfigPath -Raw | ConvertFrom-Json

function Test-PowerShellCompatibility {
    [CmdletBinding()]
    param(
        [string]$MinimumVersion = $script:RequiredPSVersion,
        [switch]$Strict
    )

    try {
        # Get current PowerShell version and edition
        $currentVersion = $PSVersionTable.PSVersion
        $edition = $PSVersionTable.PSEdition

        # Validate minimum version
        if ([version]$currentVersion -lt [version]$MinimumVersion) {
            Write-Warning "PowerShell version $currentVersion is below minimum required version $MinimumVersion"
            return $false
        }

        # Validate TLS support
        try {
            [Net.ServicePointManager]::SecurityProtocol = $script:SecurityProtocol
        }
        catch {
            Write-Warning "TLS 1.2 is not supported on this system"
            return $false
        }

        # Check execution policy
        $policy = Get-ExecutionPolicy
        if ($policy -eq 'Restricted') {
            Write-Warning "PowerShell execution policy is set to Restricted"
            return $false
        }

        # Platform-specific checks
        if ($Strict) {
            if ($IsWindows -or $env:OS -match 'Windows') {
                # Windows-specific checks
                $dotNetVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue
                if (-not $dotNetVersion -or $dotNetVersion.Release -lt 461808) {
                    Write-Warning ".NET Framework 4.7.2 or higher is required"
                    return $false
                }
            }
        }

        return $true
    }
    catch {
        Write-Error "Failed to validate PowerShell compatibility: $_"
        return $false
    }
}

function Install-RequiredModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$MinimumVersion,
        
        [switch]$AllowPrerelease,
        
        [int]$MaxRetries = $script:MaxInstallRetries,
        
        [switch]$Force
    )

    try {
        # Validate module name and version format
        if (-not [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Name)) {
            Write-Verbose "Validating module $Name version $MinimumVersion"
            
            # Check if module is already installed with correct version
            $existingModule = Get-Module -Name $Name -ListAvailable | 
                Where-Object { [version]$_.Version -ge [version]$MinimumVersion }
            
            if ($existingModule -and -not $Force) {
                Write-Verbose "Module $Name version $($existingModule.Version) is already installed"
                return $true
            }
        }

        # Set security protocol
        [Net.ServicePointManager]::SecurityProtocol = $script:SecurityProtocol

        # Prepare installation parameters
        $installParams = @{
            Name = $Name
            MinimumVersion = $MinimumVersion
            Force = $Force
            AllowPrerelease = $AllowPrerelease
            ErrorAction = 'Stop'
        }

        # Attempt installation with retry logic
        $attempt = 0
        do {
            $attempt++
            try {
                Write-Verbose "Installing $Name (Attempt $attempt of $MaxRetries)"
                Install-Module @installParams
                
                # Verify installation
                $installedModule = Get-Module -Name $Name -ListAvailable |
                    Where-Object { [version]$_.Version -ge [version]$MinimumVersion }
                
                if ($installedModule) {
                    Write-Verbose "Successfully installed $Name version $($installedModule.Version)"
                    return $true
                }
            }
            catch {
                if ($attempt -eq $MaxRetries) {
                    throw
                }
                Write-Warning "Attempt $attempt failed: $_"
                Start-Sleep -Seconds (2 * $attempt)
            }
        } while ($attempt -lt $MaxRetries)

        return $false
    }
    catch {
        Write-Error "Failed to install module $Name`: $_"
        return $false
    }
}

function Install-DevelopmentDependencies {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [switch]$Parallel,
        [switch]$NoProgress
    )

    try {
        # Validate PowerShell compatibility
        if (-not (Test-PowerShellCompatibility -Strict)) {
            throw "PowerShell environment does not meet minimum requirements"
        }

        # Set security protocol
        [Net.ServicePointManager]::SecurityProtocol = $script:SecurityProtocol

        # Get required modules from build config
        $requiredModules = $buildConfig.RequiredModules

        if (-not $requiredModules) {
            throw "No required modules found in build configuration"
        }

        Write-Verbose "Installing $($requiredModules.Count) required modules"

        # Initialize progress tracking
        $progressId = Get-Random
        $completed = 0
        $total = $requiredModules.Count

        if ($Parallel) {
            # Create installation jobs
            $jobs = @()
            $moduleQueue = [System.Collections.Queue]::new($requiredModules)

            while ($moduleQueue.Count -gt 0 -or $jobs.Count -gt 0) {
                # Start new jobs up to limit
                while ($moduleQueue.Count -gt 0 -and $jobs.Count -lt $script:ParallelJobLimit) {
                    $module = $moduleQueue.Dequeue()
                    $jobScript = {
                        param($Name, $Version, $Force)
                        Install-RequiredModule -Name $Name -MinimumVersion $Version -Force:$Force
                    }
                    $jobs += Start-Job -ScriptBlock $jobScript -ArgumentList $module.Name, $module.Version, $Force
                }

                # Check completed jobs
                $completed = @($jobs | Where-Object { $_.State -eq 'Completed' })
                foreach ($job in $completed) {
                    $result = Receive-Job -Job $job
                    if (-not $result) {
                        throw "Failed to install module from job $($job.Id)"
                    }
                    $jobs = @($jobs | Where-Object { $_.Id -ne $job.Id })
                    Remove-Job -Job $job
                }

                # Update progress
                if (-not $NoProgress) {
                    $percentComplete = [math]::Min(100, ($completed * 100 / $total))
                    Write-Progress -Id $progressId -Activity "Installing Dependencies" -Status "$completed of $total complete" -PercentComplete $percentComplete
                }

                Start-Sleep -Milliseconds 100
            }
        }
        else {
            # Sequential installation
            foreach ($module in $requiredModules) {
                if (-not (Install-RequiredModule -Name $module.Name -MinimumVersion $module.Version -Force:$Force)) {
                    throw "Failed to install module $($module.Name)"
                }
                
                # Update progress
                $completed++
                if (-not $NoProgress) {
                    $percentComplete = [math]::Min(100, ($completed * 100 / $total))
                    Write-Progress -Id $progressId -Activity "Installing Dependencies" -Status "$completed of $total complete" -PercentComplete $percentComplete
                }
            }
        }

        # Clear progress bar
        if (-not $NoProgress) {
            Write-Progress -Id $progressId -Activity "Installing Dependencies" -Completed
        }

        Write-Verbose "Successfully installed all required modules"
        return $true
    }
    catch {
        Write-Error "Failed to install development dependencies: $_"
        return $false
    }
}

# Export the main installation function
Export-ModuleMember -Function Install-DevelopmentDependencies