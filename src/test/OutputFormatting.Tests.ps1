#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.3.0' }

using module Microsoft.PowerShell.Utility

# Import test helpers
. $PSScriptRoot/TestHelpers/Test-OutputFormat.ps1
. $PSScriptRoot/TestHelpers/New-MockResponse.ps1
. $PSScriptRoot/TestHelpers/Assert-ApiCall.ps1

# Import mock data
$script:ApiResponses = Get-Content -Path "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
$script:AssetData = Get-Content -Path "$PSScriptRoot/Mocks/AssetData.json" | ConvertFrom-Json
$script:FindingData = Get-Content -Path "$PSScriptRoot/Mocks/FindingData.json" | ConvertFrom-Json

# Global test constants
$script:DefaultTableHeaders = @('Id', 'Name', 'Type', 'Status', 'LastSeen')
$script:DefaultListProperties = @('Id', 'Name', 'Type', 'Status', 'LastSeen', 'CreatedOn', 'UpdatedOn')
$script:DefaultPaginationSize = 50
$script:DefaultCultures = @('en-US', 'de-DE', 'fr-FR', 'ja-JP')

Describe 'Asset Output Formatting' {
    BeforeAll {
        # Initialize mock client
        $script:mockHttpClient = New-MockHttpClient
        
        # Set up mock responses
        Add-MockResponse -Method 'GET' -Uri '/v1/assets' -Response $ApiResponses.successResponses.getAssetListResponse
        Add-MockResponse -Method 'GET' -Uri '/v1/assets/*' -Response $ApiResponses.successResponses.getAssetResponse
    }

    Context 'Table Output Format' {
        It 'Should format single asset in table view with correct headers' {
            $result = Get-CraftAsset -Id '00000000-0000-0000-0000-000000000001'
            
            Test-TableOutput -Output $result -ExpectedHeaders $DefaultTableHeaders | Should -BeTrue
        }

        It 'Should format asset list with proper pagination display' {
            $result = Get-CraftAssetList -PageSize 50

            Test-TableOutput -Output $result -ExpectedHeaders $DefaultTableHeaders | Should -BeTrue
            Test-PaginationDisplay -Output $result -ExpectedPageSize 50 -ExpectedPage 1 | Should -BeTrue
        }

        It 'Should align columns correctly in table view' {
            $result = Get-CraftAssetList
            
            # Validate column alignment with default tolerance
            Test-TableOutput -Output $result -ExpectedHeaders $DefaultTableHeaders -FormatOptions @{
                AlignmentTolerance = 2
                MaxLineLength = 120
            } | Should -BeTrue
        }

        It 'Should handle long values with proper truncation' {
            $longNameAsset = $AssetData.assetVariations.boundaryAsset
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/boundary' -Response (
                New-MockSuccessResponse -Body $longNameAsset
            )

            $result = Get-CraftAsset -Id 'boundary'
            Test-TableOutput -Output $result -ExpectedHeaders $DefaultTableHeaders | Should -BeTrue
        }
    }

    Context 'List Output Format' {
        It 'Should format single asset in list view with all properties' {
            $result = Get-CraftAsset -Id '00000000-0000-0000-0000-000000000001' | Format-List

            Test-ListOutput -Output $result -ExpectedProperties $DefaultListProperties | Should -BeTrue
        }

        It 'Should format nested properties with proper indentation' {
            $result = Get-CraftAsset -Id '00000000-0000-0000-0000-000000000001' | Format-List
            
            Test-ListOutput -Output $result -ExpectedProperties @(
                'Properties.os',
                'Properties.ip',
                'Properties.location',
                'Properties.custom.environment'
            ) | Should -BeTrue
        }

        It 'Should handle empty and null values appropriately' {
            $minimalAsset = $AssetData.assetVariations.minimalAsset
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/minimal' -Response (
                New-MockSuccessResponse -Body $minimalAsset
            )

            $result = Get-CraftAsset -Id 'minimal' | Format-List
            Test-ListOutput -Output $result -ExpectedProperties $DefaultListProperties | Should -BeTrue
        }
    }

    Context 'Raw JSON Output Format' {
        It 'Should output valid JSON when using -Raw parameter' {
            $result = Get-CraftAsset -Id '00000000-0000-0000-0000-000000000001' -Raw

            Test-RawJsonOutput -Output $result -ExpectedSchema $AssetData.singleAsset | Should -BeTrue
        }

        It 'Should preserve all properties in JSON output' {
            $fullAsset = $AssetData.assetVariations.fullAsset
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/full' -Response (
                New-MockSuccessResponse -Body $fullAsset
            )

            $result = Get-CraftAsset -Id 'full' -Raw
            Test-RawJsonOutput -Output $result -ExpectedSchema $fullAsset | Should -BeTrue
        }

        It 'Should handle special characters in JSON output' {
            $result = Get-CraftAsset -Id '00000000-0000-0000-0000-000000000001' -Raw
            Test-RawJsonOutput -Output $result -ExpectedSchema $AssetData.singleAsset -ValidationOptions @{
                ValidateSchema = $true
                ValidateTypes = $true
                AllowExtraProperties = $false
            } | Should -BeTrue
        }
    }
}

Describe 'Finding Output Formatting' {
    BeforeAll {
        # Set up mock responses for findings
        Add-MockResponse -Method 'GET' -Uri '/v1/findings' -Response $ApiResponses.successResponses.getFindingListResponse
        Add-MockResponse -Method 'GET' -Uri '/v1/findings/*' -Response $ApiResponses.successResponses.getFindingResponse
    }

    Context 'Table Output Format' {
        It 'Should format single finding with severity color coding' {
            $result = Get-CraftFinding -Id '12345678-1234-1234-1234-123456789012'
            
            Test-TableOutput -Output $result -ExpectedHeaders @(
                'Id', 'Name', 'Severity', 'Status', 'CreatedOn'
            ) | Should -BeTrue
        }

        It 'Should format finding list with status indicators' {
            $result = Get-CraftFindingList
            
            Test-TableOutput -Output $result -ExpectedHeaders @(
                'Id', 'Name', 'Severity', 'Status', 'CreatedOn'
            ) | Should -BeTrue
        }
    }

    Context 'List Output Format' {
        It 'Should format finding details with evidence' {
            $findingWithProps = $FindingData.mockFindings.findingWithCustomProperties
            Add-MockResponse -Method 'GET' -Uri '/v1/findings/custom' -Response (
                New-MockSuccessResponse -Body $findingWithProps
            )

            $result = Get-CraftFinding -Id 'custom' | Format-List
            Test-ListOutput -Output $result -ExpectedProperties @(
                'Id', 'Name', 'FindingClass', 'Severity', 'Status',
                'Description', 'Properties', 'CreatedOn'
            ) | Should -BeTrue
        }

        It 'Should format related assets in finding output' {
            $findingWithRels = $FindingData.mockFindings.findingWithRelationships
            Add-MockResponse -Method 'GET' -Uri '/v1/findings/related' -Response (
                New-MockSuccessResponse -Body $findingWithRels
            )

            $result = Get-CraftFinding -Id 'related' | Format-List
            Test-ListOutput -Output $result -ExpectedProperties @(
                'Relationships'
            ) | Should -BeTrue
        }
    }

    Context 'Raw JSON Output Format' {
        It 'Should output complete finding data in JSON format' {
            $result = Get-CraftFinding -Id '12345678-1234-1234-1234-123456789012' -Raw
            Test-RawJsonOutput -Output $result -ExpectedSchema $FindingData.mockFindings.basicFinding | Should -BeTrue
        }
    }
}

Describe 'Culture-Specific Formatting' {
    BeforeAll {
        # Store current culture
        $script:originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
    }

    AfterAll {
        # Restore original culture
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:originalCulture
    }

    It 'Should format dates according to culture <_>' -TestCases $DefaultCultures {
        param($Culture)
        
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new($Culture)
            $result = Get-CraftAsset -Id '00000000-0000-0000-0000-000000000001'
            
            Test-CultureFormatting -Output $result -Culture $Culture | Should -BeTrue
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:originalCulture
        }
    }

    It 'Should maintain consistent alignment across cultures' {
        foreach ($culture in $DefaultCultures) {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new($culture)
            $result = Get-CraftAssetList
            
            Test-TableOutput -Output $result -ExpectedHeaders $DefaultTableHeaders | Should -BeTrue
        }
    }
}

Describe 'Pretty Print Formatting' {
    It 'Should properly indent nested objects with -PrettyPrint' {
        $result = Get-CraftAsset -Id '00000000-0000-0000-0000-000000000001' -PrettyPrint
        Test-PrettyPrintOutput -Output $result | Should -BeTrue
    }

    It 'Should format arrays with consistent indentation' {
        $result = Get-CraftAssetList -PrettyPrint
        Test-PrettyPrintOutput -Output $result | Should -BeTrue
    }

    It 'Should maintain readability for deeply nested objects' {
        $complexAsset = $AssetData.assetVariations.fullAsset
        Add-MockResponse -Method 'GET' -Uri '/v1/assets/complex' -Response (
            New-MockSuccessResponse -Body $complexAsset
        )

        $result = Get-CraftAsset -Id 'complex' -PrettyPrint
        Test-PrettyPrintOutput -Output $result -FormatOptions @{
            IndentationSpaces = 4
            MaxLineLength = 120
        } | Should -BeTrue
    }
}