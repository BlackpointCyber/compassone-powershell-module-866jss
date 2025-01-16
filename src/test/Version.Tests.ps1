#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }

BeforeAll {
    # Import test environment configuration
    . "$PSScriptRoot/TestHelpers/Initialize-TestEnvironment.ps1"
    . "$PSScriptRoot/TestConfig/pester.config.ps1"

    # Initialize test environment
    $script:testEnv = Initialize-TestEnvironment -ModulePath $PSScriptRoot/../PSCompassOne -TestPath $PSScriptRoot

    # Global test variables
    $script:ModuleManifestPath = "$PSScriptRoot/../PSCompassOne/PSCompassOne.psd1"
    $script:ModulePath = "$PSScriptRoot/../PSCompassOne/PSCompassOne.psm1"
    $script:MinimumPowerShellVersion = '5.1'
    $script:SupportedPlatforms = @('Windows', 'Linux', 'MacOS')
}

Describe 'Module Version Tests' {
    Context 'Version Consistency' {
        BeforeAll {
            $script:manifest = Import-PowerShellDataFile -Path $script:ModuleManifestPath
            $script:module = Import-Module -Name $script:ModulePath -PassThru -Force
        }

        It 'Should have consistent version in manifest and module' {
            $manifestVersion = $script:manifest.ModuleVersion
            $moduleVersion = $script:module.Version

            $manifestVersion | Should -Be $moduleVersion
        }

        It 'Should follow semantic versioning format' {
            $version = $script:manifest.ModuleVersion
            $version | Should -Match '^\d+\.\d+\.\d+$'
        }

        It 'Should have updated version history' {
            $moduleContent = Get-Content -Path $script:ModulePath -Raw
            $moduleContent | Should -Match "Version:\s+$($script:manifest.ModuleVersion)"
        }

        It 'Should meet minimum version requirements' {
            $requiredVersion = [Version]$script:MinimumPowerShellVersion
            $manifestMinVersion = [Version]$script:manifest.PowerShellVersion

            $manifestMinVersion | Should -BeGreaterOrEqual $requiredVersion
        }

        It 'Should declare correct dependency versions' {
            $dependencies = $script:manifest.RequiredModules

            # Verify SecretStore dependency
            $secretStore = $dependencies | Where-Object { $_.ModuleName -eq 'Microsoft.PowerShell.SecretStore' }
            $secretStore | Should -Not -BeNullOrEmpty
            $secretStore.ModuleVersion | Should -Be '1.0.6'

            # Verify Pester dependency for tests
            $pester = $dependencies | Where-Object { $_.ModuleName -eq 'Pester' }
            $pester | Should -Not -BeNullOrEmpty
            $pester.ModuleVersion | Should -Be '5.3.0'
        }
    }

    Context 'PowerShell Compatibility' {
        BeforeAll {
            $script:currentVersion = $PSVersionTable.PSVersion
            $script:isPS7 = $script:currentVersion.Major -ge 7
        }

        It 'Should load in PowerShell <_> on all platforms' -ForEach @('5.1', '7.0', '7.2') {
            $version = $_
            
            # Skip if current PowerShell version doesn't match test version
            if ($version -ne $script:currentVersion.ToString(2)) {
                Set-ItResult -Skipped -Because "Test requires PowerShell $version"
                return
            }

            { Import-Module $script:ModulePath -Force } | Should -Not -Throw
        }

        It 'Should support async operations in PS 7.x' {
            if (-not $script:isPS7) {
                Set-ItResult -Skipped -Because "Async operations require PowerShell 7.x"
                return
            }

            $module = Import-Module $script:ModulePath -PassThru -Force
            $asyncCommands = $module.ExportedCommands.Values | Where-Object { $_.CmdletBinding().SupportsShouldProcess }

            $asyncCommands | Should -Not -BeNullOrEmpty
            foreach ($cmd in $asyncCommands) {
                $cmd.Parameters.ContainsKey('AsJob') | Should -BeTrue
            }
        }

        It 'Should handle platform-specific paths correctly' {
            $module = Import-Module $script:ModulePath -PassThru -Force
            
            # Test path handling based on platform
            if ($IsWindows) {
                $testPath = 'C:\Test\Path'
            } else {
                $testPath = '/test/path'
            }

            # Verify path handling in module functions
            $normalizedPath = & $module { param($path) Join-Path $path 'subdir' } $testPath
            $normalizedPath | Should -Not -BeNullOrEmpty
            
            if ($IsWindows) {
                $normalizedPath | Should -Match '\\'
            } else {
                $normalizedPath | Should -Match '/'
            }
        }

        It 'Should meet version-specific performance metrics' {
            $module = Import-Module $script:ModulePath -PassThru -Force
            
            # Test basic operation performance
            $startTime = Get-Date
            1..10 | ForEach-Object {
                $null = & $module { Get-Command } # Simple operation for timing
            }
            $duration = (Get-Date) - $startTime

            # PS 7.x should be faster than PS 5.1
            if ($script:isPS7) {
                $duration.TotalMilliseconds | Should -BeLessThan 1000
            } else {
                $duration.TotalMilliseconds | Should -BeLessThan 2000
            }
        }
    }

    Context 'Platform Support' {
        BeforeAll {
            $script:currentPlatform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
        }

        It 'Should work on <_>' -ForEach $script:SupportedPlatforms {
            $platform = $_
            
            # Skip if not running on the target platform
            if ($platform -ne $script:currentPlatform) {
                Set-ItResult -Skipped -Because "Test requires $platform platform"
                return
            }

            { Import-Module $script:ModulePath -Force } | Should -Not -Throw
        }

        It 'Should handle platform-specific features correctly' {
            $module = Import-Module $script:ModulePath -PassThru -Force

            switch ($script:currentPlatform) {
                'Windows' {
                    # Test Windows-specific functionality
                    $module.PrivateData.PSData.PSEdition | Should -Contain 'Desktop'
                    if ($script:currentVersion.Major -eq 5) {
                        $module.PrivateData.PSData.PSEdition | Should -Not -Contain 'Core'
                    }
                }
                'Linux' {
                    # Test Linux-specific functionality
                    $module.PrivateData.PSData.PSEdition | Should -Contain 'Core'
                    $module.PrivateData.PSData.PSEdition | Should -Not -Contain 'Desktop'
                }
                'MacOS' {
                    # Test MacOS-specific functionality
                    $module.PrivateData.PSData.PSEdition | Should -Contain 'Core'
                    $module.PrivateData.PSData.PSEdition | Should -Not -Contain 'Desktop'
                }
            }
        }

        It 'Should validate platform-specific dependencies' {
            $manifest = Import-PowerShellDataFile -Path $script:ModuleManifestPath

            # Verify platform-specific requirements
            switch ($script:currentPlatform) {
                'Windows' {
                    if ($script:currentVersion.Major -eq 5) {
                        $manifest.PowerShellVersion | Should -Be '5.1'
                    } else {
                        $manifest.PowerShellVersion | Should -BeGreaterOrEqual '7.0'
                    }
                }
                { $_ -in @('Linux', 'MacOS') } {
                    $manifest.PowerShellVersion | Should -BeGreaterOrEqual '7.0'
                    $manifest.CompatiblePSEditions | Should -Contain 'Core'
                }
            }
        }
    }
}

AfterAll {
    # Cleanup test environment
    Remove-Module -Name PSCompassOne -Force -ErrorAction SilentlyContinue
    
    # Clean up test directories
    if ($script:testEnv.Directories) {
        foreach ($dir in $script:testEnv.Directories.Values) {
            if (Test-Path $dir) {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}