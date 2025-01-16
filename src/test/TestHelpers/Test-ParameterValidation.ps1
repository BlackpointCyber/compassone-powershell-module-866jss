# PSCompassOne Parameter Validation Test Helpers
# Version: 1.0.0
# Requires PowerShell 5.1 or PowerShell 7.x
# External Module Dependencies: Pester 5.3.0+

using namespace System.Management.Automation
using namespace System.Collections.Generic

# Import test configuration
. "$PSScriptRoot/../TestConfig/pester.config.ps1"

#region Global Configuration
$script:ValidationConfig = @{
    StrictValidation = $true
    ValidateParameterAttributes = $true
    ValidateParameterTypes = $true
    ValidateMandatoryParameters = $true
    PowerShellVersionValidation = $true
    CacheMetadata = $true
}

# Command metadata cache for performance optimization
$script:CommandMetadataCache = [Dictionary[string, CommandInfo]]::new()
#endregion

#region Helper Functions
function Get-CachedCommandMetadata {
    [CmdletBinding()]
    [OutputType([CommandInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName
    )

    if ($script:ValidationConfig.CacheMetadata -and $script:CommandMetadataCache.ContainsKey($CommandName)) {
        return $script:CommandMetadataCache[$CommandName]
    }

    $command = Get-Command -Name $CommandName -ErrorAction Stop
    if ($script:ValidationConfig.CacheMetadata) {
        $script:CommandMetadataCache[$CommandName] = $command
    }
    return $command
}

function Test-PowerShellVersionCompatibility {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Type]$Type,
        [Parameter(Mandatory)]
        [System.Type]$ExpectedType
    )

    # Handle PowerShell version-specific type mappings
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell 7.x type mappings
        $typeMap = @{
            'System.String' = @('string', 'String', 'System.String')
            'System.Int32' = @('int', 'Int32', 'System.Int32')
            'System.Boolean' = @('bool', 'Boolean', 'System.Boolean')
        }
    }
    else {
        # PowerShell 5.1 type mappings
        $typeMap = @{
            'System.String' = @('string', 'String', 'System.String')
            'System.Int32' = @('int', 'Int32', 'System.Int32')
            'System.Boolean' = @('bool', 'Boolean', 'System.Boolean')
        }
    }

    # Check type compatibility
    foreach ($mapping in $typeMap.GetEnumerator()) {
        if ($Type.FullName -eq $mapping.Key -and $ExpectedType.FullName -in $mapping.Value) {
            return $true
        }
    }

    return $Type -eq $ExpectedType -or $ExpectedType.IsAssignableFrom($Type)
}
#endregion

#region Public Functions
function Test-ParameterExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,
        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    try {
        $command = Get-CachedCommandMetadata -CommandName $CommandName
        $exists = $command.Parameters.ContainsKey($ParameterName)
        
        if (-not $exists -and $script:ValidationConfig.StrictValidation) {
            Write-Error "Parameter '$ParameterName' does not exist in command '$CommandName'"
        }
        
        return $exists
    }
    catch {
        Write-Error "Failed to validate parameter existence: $_"
        return $false
    }
}

function Test-ParameterType {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,
        [Parameter(Mandatory)]
        [string]$ParameterName,
        [Parameter(Mandatory)]
        [System.Type]$ExpectedType
    )

    try {
        $command = Get-CachedCommandMetadata -CommandName $CommandName
        if (-not $command.Parameters.ContainsKey($ParameterName)) {
            throw "Parameter '$ParameterName' not found"
        }

        $parameterType = $command.Parameters[$ParameterName].ParameterType
        $isCompatible = Test-PowerShellVersionCompatibility -Type $parameterType -ExpectedType $ExpectedType

        if (-not $isCompatible -and $script:ValidationConfig.StrictValidation) {
            Write-Error "Parameter '$ParameterName' type mismatch. Expected: $ExpectedType, Found: $parameterType"
        }

        return $isCompatible
    }
    catch {
        Write-Error "Failed to validate parameter type: $_"
        return $false
    }
}

function Test-MandatoryParameter {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,
        [Parameter(Mandatory)]
        [string]$ParameterName,
        [Parameter()]
        [string]$ParameterSetName = '__AllParameterSets'
    )

    try {
        $command = Get-CachedCommandMetadata -CommandName $CommandName
        if (-not $command.Parameters.ContainsKey($ParameterName)) {
            throw "Parameter '$ParameterName' not found"
        }

        $parameter = $command.Parameters[$ParameterName]
        $isMandatory = $false

        if ($ParameterSetName -eq '__AllParameterSets') {
            $isMandatory = $parameter.Attributes.Where({
                $_ -is [ParameterAttribute] -and $_.Mandatory
            }).Count -gt 0
        }
        else {
            $isMandatory = $parameter.Attributes.Where({
                $_ -is [ParameterAttribute] -and 
                $_.Mandatory -and 
                ($_.ParameterSetName -eq $ParameterSetName -or $_.ParameterSetName -eq '')
            }).Count -gt 0
        }

        if (-not $isMandatory -and $script:ValidationConfig.ValidateMandatoryParameters) {
            Write-Warning "Parameter '$ParameterName' is not mandatory in parameter set '$ParameterSetName'"
        }

        return $isMandatory
    }
    catch {
        Write-Error "Failed to validate mandatory parameter: $_"
        return $false
    }
}

function Test-ParameterValidation {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,
        [Parameter(Mandatory)]
        [string]$ParameterName,
        [Parameter(Mandatory)]
        [string]$ValidationAttributeType,
        [Parameter()]
        [hashtable]$ValidationParameters = @{}
    )

    try {
        $command = Get-CachedCommandMetadata -CommandName $CommandName
        if (-not $command.Parameters.ContainsKey($ParameterName)) {
            throw "Parameter '$ParameterName' not found"
        }

        $parameter = $command.Parameters[$ParameterName]
        $validationAttribute = $parameter.Attributes.Where({ $_.GetType().Name -eq $ValidationAttributeType })

        if (-not $validationAttribute -and $script:ValidationConfig.ValidateParameterAttributes) {
            Write-Error "Validation attribute '$ValidationAttributeType' not found on parameter '$ParameterName'"
            return $false
        }

        # Validate attribute parameters
        foreach ($kvp in $ValidationParameters.GetEnumerator()) {
            $attributeValue = $validationAttribute.$($kvp.Key)
            if ($attributeValue -ne $kvp.Value) {
                Write-Error "Validation attribute parameter mismatch. Parameter: $($kvp.Key), Expected: $($kvp.Value), Found: $attributeValue"
                return $false
            }
        }

        return $true
    }
    catch {
        Write-Error "Failed to validate parameter validation attributes: $_"
        return $false
    }
}

function Test-ParameterSet {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,
        [Parameter(Mandatory)]
        [string]$ParameterName,
        [Parameter(Mandatory)]
        [string[]]$ParameterSetNames
    )

    try {
        $command = Get-CachedCommandMetadata -CommandName $CommandName
        if (-not $command.Parameters.ContainsKey($ParameterName)) {
            throw "Parameter '$ParameterName' not found"
        }

        $parameter = $command.Parameters[$ParameterName]
        $parameterSets = $parameter.Attributes.Where({ $_ -is [ParameterAttribute] }).ForEach({ $_.ParameterSetName })
        
        # Handle default parameter set
        if ($parameterSets.Count -eq 0 -or ($parameterSets.Count -eq 1 -and $parameterSets[0] -eq '')) {
            $parameterSets = @('__AllParameterSets')
        }

        $matchFound = $false
        foreach ($setName in $ParameterSetNames) {
            if ($setName -in $parameterSets -or 
                ($setName -eq '__AllParameterSets' -and '' -in $parameterSets)) {
                $matchFound = $true
                break
            }
        }

        if (-not $matchFound) {
            Write-Error "Parameter '$ParameterName' not found in any of the specified parameter sets: $($ParameterSetNames -join ', ')"
        }

        return $matchFound
    }
    catch {
        Write-Error "Failed to validate parameter set membership: $_"
        return $false
    }
}
#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Test-ParameterExists',
    'Test-ParameterType',
    'Test-MandatoryParameter',
    'Test-ParameterValidation',
    'Test-ParameterSet'
)