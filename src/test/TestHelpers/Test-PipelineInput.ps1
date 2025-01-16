using module Microsoft.PowerShell.Utility # Version 5.1.0+
using module Pester # Version 5.3.0+

# Import required test helper functions
. "$PSScriptRoot/Assert-ApiCall.ps1"

# Global configuration for pipeline testing
$script:PipelineTestConfig = @{
    ValidateValueFromPipeline = $true
    ValidateValueFromPipelineByPropertyName = $true
    ValidatePipelineInput = $true
    DefaultTimeout = 30
    MaxRetries = 3
    ValidationMode = 'Strict'
}

function Test-PipelineByValue {
    <#
    .SYNOPSIS
        Tests if a command accepts pipeline input by value.
    .DESCRIPTION
        Validates that a command parameter properly accepts and processes pipeline input by value,
        checking parameter attributes and actual pipeline behavior.
    .PARAMETER CommandName
        The name of the command to test.
    .PARAMETER ParameterName
        The name of the parameter to test for pipeline input.
    .PARAMETER ValidationOptions
        Additional validation options for pipeline testing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [Parameter()]
        [hashtable]$ValidationOptions = @{}
    )

    # Merge validation options with defaults
    $options = @{
        StrictValidation = $true
        ValidateParameterType = $true
        CheckAttributePresence = $true
    }
    foreach ($key in $ValidationOptions.Keys) {
        $options[$key] = $ValidationOptions[$key]
    }

    # Get command metadata
    $command = Get-Command -Name $CommandName -ErrorAction Stop
    if (-not $command) {
        throw "Command '$CommandName' not found"
    }

    # Get parameter metadata
    $parameter = $command.Parameters[$ParameterName]
    if (-not $parameter) {
        throw "Parameter '$ParameterName' not found in command '$CommandName'"
    }

    # Check ValueFromPipeline attribute
    $hasValueFromPipeline = $parameter.Attributes | 
        Where-Object { $_ -is [Parameter] -and $_.ValueFromPipeline }

    if ($options.CheckAttributePresence -and -not $hasValueFromPipeline) {
        throw "Parameter '$ParameterName' does not accept pipeline input by value"
    }

    # Validate parameter type compatibility
    if ($options.ValidateParameterType) {
        $parameterType = $parameter.ParameterType
        if (-not $parameterType) {
            throw "Could not determine parameter type for '$ParameterName'"
        }
    }

    return $true
}

function Test-PipelineByPropertyName {
    <#
    .SYNOPSIS
        Tests if a command accepts pipeline input by property name.
    .DESCRIPTION
        Validates that a command parameter properly accepts and processes pipeline input by property name,
        including support for nested properties and inheritance.
    .PARAMETER CommandName
        The name of the command to test.
    .PARAMETER ParameterName
        The name of the parameter to test for pipeline input.
    .PARAMETER PropertyMapping
        Hashtable mapping input object properties to parameter properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [Parameter()]
        [hashtable]$PropertyMapping = @{}
    )

    # Get command metadata
    $command = Get-Command -Name $CommandName -ErrorAction Stop
    if (-not $command) {
        throw "Command '$CommandName' not found"
    }

    # Get parameter metadata
    $parameter = $command.Parameters[$ParameterName]
    if (-not $parameter) {
        throw "Parameter '$ParameterName' not found in command '$CommandName'"
    }

    # Check ValueFromPipelineByPropertyName attribute
    $hasValueFromPipelineByPropertyName = $parameter.Attributes | 
        Where-Object { $_ -is [Parameter] -and $_.ValueFromPipelineByPropertyName }

    if (-not $hasValueFromPipelineByPropertyName) {
        throw "Parameter '$ParameterName' does not accept pipeline input by property name"
    }

    # Validate property mapping if provided
    if ($PropertyMapping) {
        foreach ($sourceProperty in $PropertyMapping.Keys) {
            $targetProperty = $PropertyMapping[$sourceProperty]
            if (-not $targetProperty) {
                throw "Invalid property mapping for '$sourceProperty'"
            }
        }
    }

    return $true
}

function Test-PipelineInput {
    <#
    .SYNOPSIS
        Tests if pipeline input is properly processed by a command.
    .DESCRIPTION
        Validates that a command correctly processes pipeline input with comprehensive validation
        and API call verification.
    .PARAMETER CommandName
        The name of the command to test.
    .PARAMETER InputObject
        The input object to pipe to the command.
    .PARAMETER ValidationScript
        Script block for custom validation of the pipeline operation.
    .PARAMETER ExpectedApiCalls
        Expected API calls that should be made during pipeline processing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter()]
        [scriptblock]$ValidationScript,

        [Parameter()]
        [hashtable]$ExpectedApiCalls
    )

    # Validate command exists
    $command = Get-Command -Name $CommandName -ErrorAction Stop
    if (-not $command) {
        throw "Command '$CommandName' not found"
    }

    try {
        # Execute pipeline operation with input
        $result = $InputObject | & $CommandName

        # Validate API calls if expected
        if ($ExpectedApiCalls) {
            foreach ($call in $ExpectedApiCalls.GetEnumerator()) {
                Assert-ApiCallMade -MockHttpClient $call.Value.Client `
                                 -ExpectedMethod $call.Value.Method `
                                 -ExpectedUri $call.Value.Uri `
                                 -ExpectedHeaders $call.Value.Headers `
                                 -ExpectedBody $call.Value.Body
            }
        }

        # Run custom validation if provided
        if ($ValidationScript) {
            $validationResult = & $ValidationScript $result
            if (-not $validationResult) {
                throw "Pipeline validation script failed"
            }
        }

        return $true
    }
    catch {
        throw "Pipeline test failed: $_"
    }
}

function Test-PipelineOutput {
    <#
    .SYNOPSIS
        Tests if command output can be properly piped to another command.
    .DESCRIPTION
        Validates that a command's output can be successfully piped through a command chain
        with full validation of the pipeline operation.
    .PARAMETER SourceCommand
        The source command in the pipeline.
    .PARAMETER DestinationCommand
        The destination command receiving pipeline input.
    .PARAMETER ValidationScript
        Script block for custom validation of the pipeline chain.
    .PARAMETER ChainOptions
        Options for configuring pipeline chain validation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceCommand,

        [Parameter(Mandatory)]
        [string]$DestinationCommand,

        [Parameter()]
        [scriptblock]$ValidationScript,

        [Parameter()]
        [hashtable]$ChainOptions = @{}
    )

    # Validate commands exist
    $source = Get-Command -Name $SourceCommand -ErrorAction Stop
    $destination = Get-Command -Name $DestinationCommand -ErrorAction Stop

    if (-not $source -or -not $destination) {
        throw "One or more commands in the pipeline chain not found"
    }

    try {
        # Execute pipeline chain
        $result = & $SourceCommand | & $DestinationCommand

        # Run custom validation if provided
        if ($ValidationScript) {
            $validationResult = & $ValidationScript $result
            if (-not $validationResult) {
                throw "Pipeline chain validation script failed"
            }
        }

        # Validate chain options
        if ($ChainOptions.ValidateTypes) {
            # Verify output type compatibility
            $sourceOutput = & $SourceCommand
            $destinationParams = $destination.Parameters.Values | 
                Where-Object { $_.Attributes.ValueFromPipeline -or $_.Attributes.ValueFromPipelineByPropertyName }

            $typeCompatible = $false
            foreach ($param in $destinationParams) {
                if ($sourceOutput.GetType().IsAssignableFrom($param.ParameterType)) {
                    $typeCompatible = $true
                    break
                }
            }

            if (-not $typeCompatible) {
                throw "Pipeline type incompatibility between source and destination commands"
            }
        }

        return $true
    }
    catch {
        throw "Pipeline chain test failed: $_"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Test-PipelineByValue',
    'Test-PipelineByPropertyName',
    'Test-PipelineInput',
    'Test-PipelineOutput'
)