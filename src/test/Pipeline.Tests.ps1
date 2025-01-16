using module Microsoft.PowerShell.Utility # Version 5.1.0+
using module Pester # Version 5.3.0+

# Import test helpers and mocks
. "$PSScriptRoot/TestHelpers/Test-PipelineInput.ps1"
. "$PSScriptRoot/TestHelpers/Assert-ApiCall.ps1"
. "$PSScriptRoot/Mocks/MockHttpClient.ps1"

# Test configuration
$TestConfig = @{
    ValidateValueFromPipeline = $true
    ValidateValueFromPipelineByPropertyName = $true
    ValidatePipelineInput = $true
    ValidatePipelineOutput = $true
    PipelinePerformanceThreshold = 50
    MaxPipelineItems = 1000
    CrossVersionValidation = $true
}

Describe 'Asset Pipeline Tests' {
    BeforeAll {
        # Initialize mock HTTP client
        $mockClient = New-MockHttpClient
        $mockAssetData = Get-Content "$PSScriptRoot/Mocks/AssetData.json" | ConvertFrom-Json
        $mockResponses = Get-Content "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
    }

    BeforeEach {
        Clear-MockResponses
    }

    Context 'Get-CraftAsset Pipeline Input' {
        It 'Should accept pipeline input by value for Id parameter' {
            # Setup mock response
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/*' -Response $mockResponses.successResponses.getAssetResponse

            # Test pipeline input
            $result = Test-PipelineByValue -CommandName 'Get-CraftAsset' -ParameterName 'Id'
            $result | Should -BeTrue
        }

        It 'Should process multiple asset IDs from pipeline' {
            # Setup mock responses
            $assetIds = @('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')
            foreach ($id in $assetIds) {
                Add-MockResponse -Method 'GET' -Uri "/v1/assets/$id" -Response $mockResponses.successResponses.getAssetResponse
            }

            # Test pipeline processing
            $result = $assetIds | Get-CraftAsset
            Assert-ApiCallCount -MockHttpClient $mockClient -ExpectedCount 2 -Method 'GET'
            $result.Count | Should -Be 2
        }
    }

    Context 'Set-CraftAsset Pipeline Input' {
        It 'Should accept pipeline input by property name' {
            # Setup test data
            $asset = $mockAssetData.singleAsset
            Add-MockResponse -Method 'PATCH' -Uri '/v1/assets/*' -Response $mockResponses.successResponses.getAssetResponse

            # Test pipeline property binding
            $result = Test-PipelineByPropertyName -CommandName 'Set-CraftAsset' -ParameterName 'InputObject'
            $result | Should -BeTrue
        }

        It 'Should handle bulk asset updates via pipeline' {
            # Setup test data
            $assets = $mockAssetData.assetList.items
            foreach ($asset in $assets) {
                Add-MockResponse -Method 'PATCH' -Uri "/v1/assets/$($asset.id)" -Response $mockResponses.successResponses.getAssetResponse
            }

            # Test bulk update
            $result = $assets | Set-CraftAsset
            Assert-ApiCallCount -MockHttpClient $mockClient -ExpectedCount $assets.Count -Method 'PATCH'
        }
    }

    Context 'Asset Pipeline Chaining' {
        It 'Should support Get-CraftAsset to Set-CraftAssetTag pipeline' {
            # Setup mock responses
            Add-MockResponse -Method 'GET' -Uri '/v1/assets/*' -Response $mockResponses.successResponses.getAssetResponse
            Add-MockResponse -Method 'POST' -Uri '/v1/assets/*/tags' -Response $mockResponses.successResponses.getAssetResponse

            # Test pipeline chaining
            $result = Test-PipelineOutput -SourceCommand 'Get-CraftAsset' -DestinationCommand 'Set-CraftAssetTag' -ValidationScript {
                param($Output)
                return $null -ne $Output
            }
            $result | Should -BeTrue
        }
    }

    Context 'Pipeline Performance' {
        It 'Should handle large datasets within performance threshold' {
            # Generate large dataset
            $largeDataset = 1..$TestConfig.PipelinePerformanceThreshold | ForEach-Object {
                $mockAssetData.singleAsset.Clone()
            }

            # Setup mock responses
            foreach ($item in $largeDataset) {
                Add-MockResponse -Method 'GET' -Uri "/v1/assets/$($item.id)" -Response $mockResponses.successResponses.getAssetResponse
            }

            # Measure pipeline performance
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $result = $largeDataset | Get-CraftAsset
            $timer.Stop()

            $itemsPerSecond = $largeDataset.Count / $timer.Elapsed.TotalSeconds
            $itemsPerSecond | Should -BeGreaterThan 50
        }
    }
}

Describe 'Finding Pipeline Tests' {
    BeforeAll {
        # Initialize mock HTTP client
        $mockClient = New-MockHttpClient
        $mockFindingData = Get-Content "$PSScriptRoot/Mocks/FindingData.json" | ConvertFrom-Json
        $mockResponses = Get-Content "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
    }

    BeforeEach {
        Clear-MockResponses
    }

    Context 'Get-CraftFinding Pipeline Input' {
        It 'Should accept pipeline input by value for Id parameter' {
            Add-MockResponse -Method 'GET' -Uri '/v1/findings/*' -Response $mockResponses.successResponses.getFindingResponse

            $result = Test-PipelineByValue -CommandName 'Get-CraftFinding' -ParameterName 'Id'
            $result | Should -BeTrue
        }

        It 'Should process multiple finding IDs from pipeline' {
            $findingIds = $mockFindingData.mockFindings.findingList | Select-Object -ExpandProperty id
            foreach ($id in $findingIds) {
                Add-MockResponse -Method 'GET' -Uri "/v1/findings/$id" -Response $mockResponses.successResponses.getFindingResponse
            }

            $result = $findingIds | Get-CraftFinding
            Assert-ApiCallCount -MockHttpClient $mockClient -ExpectedCount $findingIds.Count -Method 'GET'
        }
    }

    Context 'Finding Pipeline Chaining' {
        It 'Should support Get-CraftFinding to Set-CraftFindingTag pipeline' {
            Add-MockResponse -Method 'GET' -Uri '/v1/findings/*' -Response $mockResponses.successResponses.getFindingResponse
            Add-MockResponse -Method 'POST' -Uri '/v1/findings/*/tags' -Response $mockResponses.successResponses.getFindingResponse

            $result = Test-PipelineOutput -SourceCommand 'Get-CraftFinding' -DestinationCommand 'Set-CraftFindingTag'
            $result | Should -BeTrue
        }
    }
}

Describe 'Relationship Pipeline Tests' {
    BeforeAll {
        $mockClient = New-MockHttpClient
        $mockResponses = Get-Content "$PSScriptRoot/Mocks/ApiResponses.json" | ConvertFrom-Json
    }

    BeforeEach {
        Clear-MockResponses
    }

    Context 'Get-CraftRelationship Pipeline Input' {
        It 'Should accept pipeline input by value for Id parameter' {
            Add-MockResponse -Method 'GET' -Uri '/v1/relationships/*' -Response $mockResponses.successResponses.getAssetResponse

            $result = Test-PipelineByValue -CommandName 'Get-CraftRelationship' -ParameterName 'Id'
            $result | Should -BeTrue
        }

        It 'Should handle relationship property binding' {
            $relationships = $mockAssetData.assetVariations.relationshipAsset.relationships
            foreach ($rel in $relationships) {
                Add-MockResponse -Method 'GET' -Uri "/v1/relationships/$($rel.id)" -Response $mockResponses.successResponses.getAssetResponse
            }

            $result = Test-PipelineByPropertyName -CommandName 'Get-CraftRelationship' -ParameterName 'Id'
            $result | Should -BeTrue
        }
    }

    Context 'Cross-Version Pipeline Support' {
        It 'Should maintain pipeline functionality across PowerShell versions' {
            if ($TestConfig.CrossVersionValidation) {
                $psVersions = @('5.1', '7.0', '7.2')
                foreach ($version in $psVersions) {
                    # Test basic pipeline operation in each version
                    Add-MockResponse -Method 'GET' -Uri '/v1/assets/*' -Response $mockResponses.successResponses.getAssetResponse
                    
                    $result = Test-PipelineInput -CommandName 'Get-CraftAsset' -InputObject '00000000-0000-0000-0000-000000000001'
                    $result | Should -BeTrue
                }
            }
        }
    }
}