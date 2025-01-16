#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Security
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

# Microsoft.PowerShell.Security v7.0.0
Import-Module Microsoft.PowerShell.Security

# Global paths
$SigningRoot = "$PSScriptRoot/.."
$SignedFilesPath = "$SigningRoot/signed"
$LogPath = "$SigningRoot/logs/signing.log"

# Import signing configuration
$SigningConfiguration = Get-Content -Path "$SigningRoot/config/code.sign.settings.json" | ConvertFrom-Json

function Initialize-SigningEnvironment {
    [CmdletBinding()]
    param()

    try {
        # Validate PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            throw "PowerShell 7.0 or higher is required for secure code signing"
        }

        # Create and secure logging directory
        if (-not (Test-Path $LogPath)) {
            New-Item -Path (Split-Path $LogPath -Parent) -ItemType Directory -Force | Out-Null
            $null = New-Item -Path $LogPath -ItemType File -Force
            $acl = Get-Acl -Path $LogPath
            $acl.SetAccessRuleProtection($true, $false)
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","Allow")
            $acl.AddAccessRule($adminRule)
            Set-Acl -Path $LogPath -AclObject $acl
        }

        # Create and secure signed files directory
        if (-not (Test-Path $SignedFilesPath)) {
            New-Item -Path $SignedFilesPath -ItemType Directory -Force | Out-Null
            $acl = Get-Acl -Path $SignedFilesPath
            $acl.SetAccessRuleProtection($true, $false)
            $acl.AddAccessRule($adminRule)
            Set-Acl -Path $SignedFilesPath -AclObject $acl
        }

        # Validate configuration schema
        $requiredProps = @('Certificate', 'TimestampServer', 'SigningAlgorithm', 'FileTypes')
        foreach ($prop in $requiredProps) {
            if (-not $SigningConfiguration.PSObject.Properties[$prop]) {
                throw "Missing required configuration property: $prop"
            }
        }

        # Validate certificate store accessibility
        $store = Get-Item -Path "Cert:\$($SigningConfiguration.Certificate.StoreLocation)\$($SigningConfiguration.Certificate.StoreName)" -ErrorAction Stop

        # Test timestamp server connectivity
        $timestampTest = Test-NetConnection -ComputerName ([uri]$SigningConfiguration.TimestampServer).Host -Port 443
        if (-not $timestampTest.TcpTestSucceeded) {
            throw "Cannot connect to timestamp server: $($SigningConfiguration.TimestampServer)"
        }

        Write-Log "Signing environment initialized successfully"
    }
    catch {
        Write-Log "Failed to initialize signing environment: $_" -Level Error
        throw
    }
}

function Get-SigningCertificate {
    [CmdletBinding()]
    param()

    try {
        # Retrieve certificate
        $cert = Get-Item -Path "Cert:\$($SigningConfiguration.Certificate.StoreLocation)\$($SigningConfiguration.Certificate.StoreName)\$($SigningConfiguration.Certificate.Thumbprint)" -ErrorAction Stop

        # Validate certificate purpose
        if ($cert.Extensions.Where({$_.Oid.FriendlyName -eq "Enhanced Key Usage"}).EnhancedKeyUsages.FriendlyName -notcontains "Code Signing") {
            throw "Certificate is not valid for code signing"
        }

        # Validate certificate dates
        if ($cert.NotBefore -gt (Get-Date) -or $cert.NotAfter -lt (Get-Date)) {
            throw "Certificate is not within its validity period"
        }

        # Validate certificate chain
        $chain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationFlag = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::EntireChain
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
        $chain.ChainPolicy.UrlRetrievalTimeout = New-TimeSpan -Seconds 30

        if (-not $chain.Build($cert)) {
            $chainErrors = $chain.ChainStatus | ForEach-Object { $_.StatusInformation }
            throw "Certificate chain validation failed: $($chainErrors -join '; ')"
        }

        # Verify private key
        if (-not $cert.HasPrivateKey) {
            throw "Certificate does not have an accessible private key"
        }

        Write-Log "Successfully validated signing certificate with thumbprint: $($cert.Thumbprint)"
        return $cert
    }
    catch {
        Write-Log "Failed to validate signing certificate: $_" -Level Error
        throw
    }
    finally {
        if ($chain) { $chain.Dispose() }
    }
}

function Sign-ModuleFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    try {
        # Validate file
        if (-not (Test-Path $FilePath)) {
            throw "File not found: $FilePath"
        }

        # Calculate pre-signing hash
        $preHash = Get-FileHash -Path $FilePath -Algorithm SHA512

        # Get signing certificate
        $cert = Get-SigningCertificate

        # Sign file with retry logic
        $attempt = 1
        $signed = $false
        do {
            try {
                $sig = Set-AuthenticodeSignature -FilePath $FilePath -Certificate $cert `
                    -HashAlgorithm $SigningConfiguration.SigningAlgorithm `
                    -TimestampServer $SigningConfiguration.TimestampServer `
                    -IncludeChain All -ErrorAction Stop

                if ($sig.Status -eq 'Valid') {
                    $signed = $true
                    break
                }
            }
            catch {
                Write-Log "Signing attempt $attempt failed: $_" -Level Warning
                Start-Sleep -Seconds ($attempt * 2)
            }
            $attempt++
        } while ($attempt -le 3)

        if (-not $signed) {
            throw "Failed to sign file after 3 attempts"
        }

        # Verify signature
        $verify = Get-AuthenticodeSignature -FilePath $FilePath
        if ($verify.Status -ne 'Valid' -or -not $verify.TimeStamperCertificate) {
            throw "Signature verification failed"
        }

        # Calculate post-signing hash
        $postHash = Get-FileHash -Path $FilePath -Algorithm SHA512
        if ($preHash.Hash -eq $postHash.Hash) {
            throw "File content unchanged after signing"
        }

        Write-Log "Successfully signed file: $FilePath"
        return $true
    }
    catch {
        Write-Log "Failed to sign file $FilePath`: $_" -Level Error
        return $false
    }
}

function Sign-ModuleFiles {
    [CmdletBinding()]
    param()

    try {
        # Initialize environment
        Initialize-SigningEnvironment

        # Get files to sign from build output
        $buildOutputPath = "$SigningRoot/build/output"
        $filesToSign = Get-ChildItem -Path $buildOutputPath -Recurse |
            Where-Object { $SigningConfiguration.FileTypes -contains $_.Extension }

        Write-Log "Found $($filesToSign.Count) files to sign"

        # Create signing jobs
        $jobs = @()
        foreach ($file in $filesToSign) {
            $jobs += Start-Job -ScriptBlock {
                param($file, $script)
                . ([ScriptBlock]::Create($script))
                Sign-ModuleFile -FilePath $file.FullName
            } -ArgumentList $file, (Get-Content Function:\Sign-ModuleFile)
        }

        # Monitor jobs with progress
        $completed = 0
        while ($jobs | Where-Object State -eq 'Running') {
            $completed = ($jobs | Where-Object State -eq 'Completed').Count
            Write-Progress -Activity "Signing files" -Status "$completed of $($jobs.Count) completed" `
                -PercentComplete (($completed / $jobs.Count) * 100)
            Start-Sleep -Seconds 1
        }

        # Process results
        $results = $jobs | Receive-Job
        $successCount = ($results | Where-Object { $_ -eq $true }).Count
        $failureCount = ($results | Where-Object { $_ -eq $false }).Count

        Write-Log "Signing completed. Success: $successCount, Failures: $failureCount"

        # Clean up
        $jobs | Remove-Job
        
        if ($failureCount -gt 0) {
            throw "Failed to sign $failureCount files"
        }
    }
    catch {
        Write-Log "Module signing failed: $_" -Level Error
        throw
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Level = 'Information'
    )

    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')|$Level|$Message"
    Add-Content -Path $LogPath -Value $logMessage
    
    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message }
        default { Write-Verbose $Message }
    }
}

# Export main signing function
Export-ModuleMember -Function Sign-ModuleFiles