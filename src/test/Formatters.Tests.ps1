#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }

using module Microsoft.PowerShell.Utility # Version 5.1.0+

# Import test helpers
. $PSScriptRoot/TestHelpers/Test-OutputFormat.ps1
. $PSScriptRoot/TestHelpers/New-MockResponse.ps1
. $PSScriptRoot/TestHelpers/Test-ApiResponse.ps1

# Load mock data
$script:ApiResponses = Get-Content -Path "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
$script:AssetData = Get-Content -Path "$PSScriptRoot/Mocks/AssetData.json" | ConvertFrom-Json
$script:FindingData = Get-Content -Path "$PSScriptRoot/Mocks/FindingData.json" | ConvertFrom-Json

Describe 'Output Formatting Tests' -Tag @('Formatting', 'Output') {
    BeforeAll {
        # Set default validation rules
        $script:DefaultTableHeaders = @('Id', 'Name', 'Type', 'Status', 'LastSeen')
        $script:ValidOutputFormats = @('Table', 'List', 'Raw')
        $script:MaxLineLength = 120
        $script:IndentationSize = 4
        $script:TestTimeout = 30
    }

    Context 'Table Format Tests' {
        BeforeEach {
            # Create mock response with table data
            $mockResponse = New-MockSuccessResponse -Body $AssetData.assetList -PSFormatting @{
                formatType = 'Table'
                defaultView = 'Table'
            }
        }

        It 'Should format asset list as table with correct headers' {
            $output = $mockResponse | Format-Table
            $result = Test-TableOutput -Output $output -ExpectedHeaders $DefaultTableHeaders
            $result | Should -BeTrue -Because 'Table output should have correct headers'
        }

        It 'Should align table columns correctly' {
            $output = $mockResponse | Format-Table
            $result = Test-TableOutput -Output $output -ExpectedHeaders $DefaultTableHeaders -FormatOptions @{
                AlignmentTolerance = 2
                MaxLineLength = $MaxLineLength
            }
            $result | Should -BeTrue -Because 'Table columns should be properly aligned'
        }

        It 'Should handle culture-specific formatting' {
            # Test with different cultures
            $cultures = @('en-US', 'de-DE', 'fr-FR')
            foreach ($culture in $cultures) {
                $prevCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new($culture)
                    $output = $mockResponse | Format-Table
                    $result = Test-TableOutput -Output $output -ExpectedHeaders $DefaultTableHeaders
                    $result | Should -BeTrue -Because "Table formatting should work with $culture culture"
                }
                finally {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $prevCulture
                }
            }
        }

        It 'Should respect maximum line length' {
            $output = $mockResponse | Format-Table
            $lines = $output | Out-String -Width $MaxLineLength | Split-String -Separator "`n"
            $lines | ForEach-Object {
                $_.Length | Should -BeLessOrEqual $MaxLineLength -Because 'Lines should not exceed maximum length'
            }
        }
    }

    Context 'List Format Tests' {
        BeforeEach {
            # Create mock response with detailed asset data
            $mockResponse = New-MockSuccessResponse -Body $AssetData.singleAsset -PSFormatting @{
                formatType = 'List'
                defaultView = 'List'
            }
        }

        It 'Should format single asset as list with proper indentation' {
            $output = $mockResponse | Format-List
            $result = Test-ListOutput -Output $output -ExpectedProperties @(
                'Id', 'Name', 'AssetClass', 'Status', 'Properties', 'Tags'
            ) -FormatOptions @{
                IndentationSpaces = $IndentationSize
            }
            $result | Should -BeTrue -Because 'List output should be properly formatted'
        }

        It 'Should handle nested objects in list format' {
            $output = $mockResponse | Format-List
            $result = Test-ListOutput -Output $output -ExpectedProperties @(
                'Properties.os', 'Properties.ip', 'Properties.custom.environment'
            )
            $result | Should -BeTrue -Because 'Nested objects should be properly formatted'
        }

        It 'Should format arrays and collections correctly' {
            $output = $mockResponse | Format-List
            $result = Test-ListOutput -Output $output -ExpectedProperties @(
                'Tags', 'Relationships'
            )
            $result | Should -BeTrue -Because 'Arrays should be properly formatted'
        }
    }

    Context 'Raw JSON Format Tests' {
        BeforeEach {
            # Create mock response with raw data
            $mockResponse = New-MockSuccessResponse -Body $AssetData.singleAsset
        }

        It 'Should output valid JSON when using raw format' {
            $output = $mockResponse | ConvertTo-Json -Depth 10
            $result = Test-RawJsonOutput -Output $output -ExpectedSchema $AssetData.singleAsset
            $result | Should -BeTrue -Because 'Output should be valid JSON'
        }

        It 'Should preserve all properties in JSON output' {
            $output = $mockResponse | ConvertTo-Json -Depth 10
            $result = Test-RawJsonOutput -Output $output -ExpectedSchema $AssetData.singleAsset -ValidationOptions @{
                ValidateSchema = $true
                AllowExtraProperties = $false
                ValidateTypes = $true
            }
            $result | Should -BeTrue -Because 'All properties should be preserved'
        }

        It 'Should handle special characters in JSON' {
            # Add special characters to test data
            $testData = $AssetData.singleAsset.Clone()
            $testData.name = 'Test"Asset\with/special?chars'
            $mockResponse = New-MockSuccessResponse -Body $testData
            
            $output = $mockResponse | ConvertTo-Json -Depth 10
            $result = Test-RawJsonOutput -Output $output -ExpectedSchema $testData
            $result | Should -BeTrue -Because 'Special characters should be properly escaped'
        }
    }

    Context 'Pretty Print Format Tests' {
        BeforeEach {
            # Create mock response with complex nested data
            $mockResponse = New-MockSuccessResponse -Body $AssetData.assetVariations.fullAsset -PSFormatting @{
                formatType = 'Default'
                defaultView = 'Default'
            }
        }

        It 'Should apply consistent indentation in pretty print' {
            $output = $mockResponse | ConvertTo-Json -Depth 10
            $result = Test-PrettyPrintOutput -Output $output -FormatOptions @{
                IndentationSpaces = $IndentationSize
                MaxLineLength = $MaxLineLength
            }
            $result | Should -BeTrue -Because 'Pretty print should have consistent indentation'
        }

        It 'Should format nested objects with proper hierarchy' {
            $output = $mockResponse | ConvertTo-Json -Depth 10
            $result = Test-PrettyPrintOutput -Output $output
            $result | Should -BeTrue -Because 'Nested objects should maintain proper hierarchy'
        }

        It 'Should handle large objects within line length limits' {
            $output = $mockResponse | ConvertTo-Json -Depth 10
            $lines = $output -split "`n"
            $lines | ForEach-Object {
                $_.Length | Should -BeLessOrEqual $MaxLineLength -Because 'Lines should not exceed maximum length'
            }
        }
    }

    Context 'Cross-Platform Formatting Tests' {
        It 'Should handle different line endings' {
            $lineEndings = @("`n", "`r`n")
            foreach ($ending in $lineEndings) {
                $mockResponse = New-MockSuccessResponse -Body $AssetData.singleAsset
                $output = ($mockResponse | ConvertTo-Json) -replace "`r?`n", $ending
                
                $result = Test-PrettyPrintOutput -Output $output
                $result | Should -BeTrue -Because "Output should handle $ending line endings"
            }
        }

        It 'Should maintain consistent spacing across platforms' {
            $mockResponse = New-MockSuccessResponse -Body $AssetData.singleAsset
            $output = $mockResponse | Format-Table
            
            # Test with both spaces and tabs
            $result = Test-TableOutput -Output $output -ExpectedHeaders $DefaultTableHeaders
            $result | Should -BeTrue -Because 'Spacing should be consistent'
        }
    }
}