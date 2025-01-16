<#
.SYNOPSIS
    Comprehensive validation test suite for PSCompassOne module.
.DESCRIPTION
    Implements extensive testing of parameter validation, input validation, and schema validation
    with cross-platform compatibility and security controls verification.
.NOTES
    Version: 1.0.0
    Requires: Pester 5.3.0+, PowerShell 5.1 or 7.x
#>

# Import required modules and test helpers
using module Pester # Version 5.3.0
. "$PSScriptRoot/TestHelpers/Test-ParameterValidation.ps1"
. "$PSScriptRoot/TestConfig/pester.config.ps1"

BeforeAll {
    # Initialize test configuration
    $script:TestConfig = New-PSCompassOnePesterConfig
}

Describe 'Asset ID Validation Tests' {
    BeforeAll {
        $validUuid = '123e4567-e89b-12d3-a456-426614174000'
        $invalidUuids = @(
            'not-a-uuid',
            '123e4567-e89b-12d3-a456', # Incomplete
            '123e4567-e89b-12d3-a456-42661417400g' # Invalid character
        )
    }

    Context 'UUID Format Validation' {
        It 'Should validate correct UUID format' {
            $result = Test-ParameterValidation -CommandName 'Get-CraftAsset' -ParameterName 'Id' `
                -ValidationAttributeType 'ValidatePatternAttribute' `
                -ValidationParameters @{
                    RegexPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
                }
            $result | Should -BeTrue
        }

        It 'Should reject invalid UUID formats' {
            foreach ($invalidUuid in $invalidUuids) {
                { Get-CraftAsset -Id $invalidUuid } | Should -Throw -ErrorId 'ParameterArgumentValidationError'
            }
        }
    }

    Context 'Mandatory Parameter Requirements' {
        It 'Should require Asset ID parameter' {
            $result = Test-MandatoryParameter -CommandName 'Get-CraftAsset' -ParameterName 'Id'
            $result | Should -BeTrue
        }

        It 'Should not accept null or empty Asset ID' {
            { Get-CraftAsset -Id $null } | Should -Throw
            { Get-CraftAsset -Id '' } | Should -Throw
        }
    }

    Context 'Pipeline Input Support' {
        It 'Should accept Asset ID from pipeline' {
            $result = Test-ParameterValidation -CommandName 'Get-CraftAsset' -ParameterName 'Id' `
                -ValidationAttributeType 'ParameterAttribute' `
                -ValidationParameters @{
                    ValueFromPipeline = $true
                }
            $result | Should -BeTrue
        }
    }
}

Describe 'Page Size Validation Tests' {
    Context 'Range Validation' {
        It 'Should enforce page size range (1-100)' {
            $result = Test-ParameterValidation -CommandName 'Get-CraftAssetList' -ParameterName 'PageSize' `
                -ValidationAttributeType 'ValidateRangeAttribute' `
                -ValidationParameters @{
                    MinRange = 1
                    MaxRange = 100
                }
            $result | Should -BeTrue
        }

        It 'Should reject out-of-range values' {
            { Get-CraftAssetList -PageSize 0 } | Should -Throw
            { Get-CraftAssetList -PageSize 101 } | Should -Throw
        }
    }

    Context 'Type Validation' {
        It 'Should validate integer type' {
            $result = Test-ParameterType -CommandName 'Get-CraftAssetList' -ParameterName 'PageSize' `
                -ExpectedType ([System.Int32])
            $result | Should -BeTrue
        }

        It 'Should reject non-integer values' {
            { Get-CraftAssetList -PageSize "50" } | Should -Throw
            { Get-CraftAssetList -PageSize 50.5 } | Should -Throw
        }
    }

    Context 'Default Value Handling' {
        It 'Should use default page size of 50' {
            $command = Get-Command Get-CraftAssetList
            $defaultValue = $command.Parameters['PageSize'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.PSDefaultValueAttribute] } |
                Select-Object -ExpandProperty Value
            $defaultValue | Should -Be 50
        }
    }
}

Describe 'Sort Field Validation Tests' {
    Context 'Allowed Values Validation' {
        It 'Should validate allowed sort fields' {
            $result = Test-ParameterValidation -CommandName 'Get-CraftAssetList' -ParameterName 'SortBy' `
                -ValidationAttributeType 'ValidateSetAttribute' `
                -ValidationParameters @{
                    ValidValues = @('name', 'createdOn', 'status')
                }
            $result | Should -BeTrue
        }

        It 'Should reject invalid sort fields' {
            { Get-CraftAssetList -SortBy 'invalid' } | Should -Throw
        }
    }

    Context 'Case Sensitivity' {
        It 'Should handle case-insensitive sort fields' {
            { Get-CraftAssetList -SortBy 'NAME' } | Should -Not -Throw
            { Get-CraftAssetList -SortBy 'createdon' } | Should -Not -Throw
        }
    }
}

Describe 'JSON Schema Validation Tests' {
    BeforeAll {
        $validJson = @'
{
    "asset": {
        "assetClass": "DEVICE",
        "name": "TestServer",
        "accountId": "acc123",
        "customerId": "cust456"
    }
}
'@
        $invalidJson = @'
{
    "asset": {
        "name": "TestServer"
    }
}
'@
    }

    Context 'Schema Structure Validation' {
        It 'Should validate complete JSON structure' {
            { New-CraftAsset -JsonBody $validJson } | Should -Not -Throw
        }

        It 'Should reject incomplete JSON structure' {
            { New-CraftAsset -JsonBody $invalidJson } | Should -Throw
        }
    }

    Context 'Required Properties Validation' {
        It 'Should validate required properties' {
            $result = Test-ParameterValidation -CommandName 'New-CraftAsset' -ParameterName 'JsonBody' `
                -ValidationAttributeType 'ValidateScriptAttribute'
            $result | Should -BeTrue
        }
    }
}

Describe 'API URL Validation Tests' {
    Context 'HTTPS Requirement' {
        It 'Should require HTTPS URLs' {
            $result = Test-ParameterValidation -CommandName 'Connect-CompassOne' -ParameterName 'Url' `
                -ValidationAttributeType 'ValidatePatternAttribute' `
                -ValidationParameters @{
                    RegexPattern = '^https://'
                }
            $result | Should -BeTrue
        }

        It 'Should reject non-HTTPS URLs' {
            { Connect-CompassOne -Url 'http://api.example.com' } | Should -Throw
        }
    }
}

Describe 'DateTime Validation Tests' {
    Context 'ISO 8601 Format Validation' {
        It 'Should validate ISO 8601 format' {
            $result = Test-ParameterValidation -CommandName 'Get-CraftAssetList' -ParameterName 'CreatedAfter' `
                -ValidationAttributeType 'ValidatePatternAttribute' `
                -ValidationParameters @{
                    RegexPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
                }
            $result | Should -BeTrue
        }

        It 'Should reject invalid datetime formats' {
            { Get-CraftAssetList -CreatedAfter '2024-01-20' } | Should -Throw
            { Get-CraftAssetList -CreatedAfter '01/20/2024' } | Should -Throw
        }
    }

    Context 'Cross-Platform DateTime Handling' {
        It 'Should handle UTC conversion consistently' {
            $date = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            { Get-CraftAssetList -CreatedAfter $date } | Should -Not -Throw
        }
    }
}