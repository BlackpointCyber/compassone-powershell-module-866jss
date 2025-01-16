#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }

BeforeAll {
    # Import test helpers and configuration
    . "$PSScriptRoot/TestHelpers/Test-ParameterValidation.ps1"
    $TestConfig = New-PSCompassOnePesterConfig
}

Describe 'Asset Command Parameters' {
    Context 'Get-CraftAsset Parameters' {
        BeforeAll {
            $command = 'Get-CraftAsset'
        }

        It 'Should have Id parameter with UUID format validation' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'Id' -ValidationAttributeType 'ValidatePatternAttribute' -ValidationParameters @{
                RegexPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
            }
            $result | Should -BeTrue
        }

        It 'Should have Id as mandatory parameter' {
            Test-MandatoryParameter -CommandName $command -ParameterName 'Id' | Should -BeTrue
        }

        It 'Should have correct parameter types' {
            Test-ParameterType -CommandName $command -ParameterName 'Id' -ExpectedType ([string]) | Should -BeTrue
            Test-ParameterType -CommandName $command -ParameterName 'PrettyPrint' -ExpectedType ([switch]) | Should -BeTrue
        }
    }

    Context 'Get-CraftAssetList Parameters' {
        BeforeAll {
            $command = 'Get-CraftAssetList'
        }

        It 'Should validate PageSize range (1-100)' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'PageSize' -ValidationAttributeType 'ValidateRangeAttribute' -ValidationParameters @{
                MinRange = 1
                MaxRange = 100
            }
            $result | Should -BeTrue
        }

        It 'Should validate SortBy allowed values' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'SortBy' -ValidationAttributeType 'ValidateSetAttribute' -ValidationParameters @{
                ValidValues = @('name', 'createdOn', 'status')
            }
            $result | Should -BeTrue
        }
    }

    Context 'New-CraftAsset Parameters' {
        BeforeAll {
            $command = 'New-CraftAsset'
        }

        It 'Should have mandatory JsonBody parameter' {
            Test-MandatoryParameter -CommandName $command -ParameterName 'JsonBody' | Should -BeTrue
        }

        It 'Should validate JsonBody schema' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'JsonBody' -ValidationAttributeType 'ValidateScriptAttribute'
            $result | Should -BeTrue
        }
    }
}

Describe 'Finding Command Parameters' {
    Context 'Get-CraftFinding Parameters' {
        BeforeAll {
            $command = 'Get-CraftFinding'
        }

        It 'Should have Id parameter with UUID format validation' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'Id' -ValidationAttributeType 'ValidatePatternAttribute' -ValidationParameters @{
                RegexPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
            }
            $result | Should -BeTrue
        }

        It 'Should validate Severity levels' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'Severity' -ValidationAttributeType 'ValidateSetAttribute' -ValidationParameters @{
                ValidValues = @('Low', 'Medium', 'High', 'Critical')
            }
            $result | Should -BeTrue
        }

        It 'Should validate Status values' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'Status' -ValidationAttributeType 'ValidateSetAttribute' -ValidationParameters @{
                ValidValues = @('Open', 'Closed', 'InProgress')
            }
            $result | Should -BeTrue
        }
    }

    Context 'New-CraftFinding Parameters' {
        BeforeAll {
            $command = 'New-CraftFinding'
        }

        It 'Should have mandatory JsonBody parameter' {
            Test-MandatoryParameter -CommandName $command -ParameterName 'JsonBody' | Should -BeTrue
        }

        It 'Should validate JsonBody schema' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'JsonBody' -ValidationAttributeType 'ValidateScriptAttribute'
            $result | Should -BeTrue
        }
    }
}

Describe 'Configuration Command Parameters' {
    Context 'Set-CraftConfiguration Parameters' {
        BeforeAll {
            $command = 'Set-CraftConfiguration'
        }

        It 'Should validate ApiUrl HTTPS format' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'ApiUrl' -ValidationAttributeType 'ValidatePatternAttribute' -ValidationParameters @{
                RegexPattern = '^https://'
            }
            $result | Should -BeTrue
        }

        It 'Should have ApiToken as SecureString type' {
            Test-ParameterType -CommandName $command -ParameterName 'ApiToken' -ExpectedType ([System.Security.SecureString]) | Should -BeTrue
        }

        It 'Should have mandatory parameters' {
            Test-MandatoryParameter -CommandName $command -ParameterName 'ApiUrl' | Should -BeTrue
            Test-MandatoryParameter -CommandName $command -ParameterName 'ApiToken' | Should -BeTrue
        }
    }

    Context 'Get-CraftConfiguration Parameters' {
        BeforeAll {
            $command = 'Get-CraftConfiguration'
        }

        It 'Should have correct parameter sets' {
            Test-ParameterSet -CommandName $command -ParameterName 'Scope' -ParameterSetNames @('User', 'System') | Should -BeTrue
        }

        It 'Should validate Scope values' {
            $result = Test-ParameterValidation -CommandName $command -ParameterName 'Scope' -ValidationAttributeType 'ValidateSetAttribute' -ValidationParameters @{
                ValidValues = @('User', 'System')
            }
            $result | Should -BeTrue
        }
    }
}

Describe 'Cross-Platform Parameter Compatibility' {
    Context 'Path Parameters' {
        It 'Should use platform-agnostic path separators' {
            $commands = @('Import-CraftConfiguration', 'Export-CraftConfiguration')
            foreach ($command in $commands) {
                $result = Test-ParameterValidation -CommandName $command -ParameterName 'Path' -ValidationAttributeType 'ValidateScriptAttribute'
                $result | Should -BeTrue
            }
        }
    }

    Context 'DateTime Parameters' {
        It 'Should validate ISO 8601 format' {
            $commands = @('Get-CraftAssetList', 'Get-CraftFindingList')
            foreach ($command in $commands) {
                $result = Test-ParameterValidation -CommandName $command -ParameterName 'StartDate' -ValidationAttributeType 'ValidatePatternAttribute' -ValidationParameters @{
                    RegexPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
                }
                $result | Should -BeTrue
            }
        }
    }
}