#Requires -Version 5.1
using module Microsoft.PowerShell.Utility # Version 5.1.0+
using module Pester # Version 5.3.0+

# Import required test helpers
. $PSScriptRoot/New-MockResponse.ps1
. $PSScriptRoot/Test-ApiResponse.ps1

# Global validation constants
Set-Variable -Name ValidOutputFormats -Value @('Table', 'List', 'Raw', 'PrettyPrint') -Option Constant
Set-Variable -Name DefaultTableHeaders -Value @('Id', 'Name', 'Type', 'Status', 'LastSeen') -Option Constant
Set-Variable -Name FormatValidationRules -Value @{
    AlignmentTolerance = 2
    IndentationSpaces = 4
    MaxLineLength = 120
} -Option Constant

function Test-TableOutput {
    <#
    .SYNOPSIS
        Tests if the cmdlet output is correctly formatted as a PowerShell table.
    .DESCRIPTION
        Performs comprehensive validation of PowerShell table output including column alignment,
        header formatting, and data presentation according to CompassOne standards.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Output,

        [Parameter(Mandatory)]
        [string[]]$ExpectedHeaders,

        [Parameter()]
        [hashtable]$FormatOptions = $FormatValidationRules
    )

    # Validate output is table format
    if (-not ($Output | Get-Member | Where-Object { $_.MemberType -eq 'MemberSet' -and $_.Name -eq 'FormatStartData' })) {
        Should -Fail -Because "Output is not in table format"
        return $false
    }

    # Extract table data
    $tableData = $Output | Format-Table | Out-String -Width $FormatOptions.MaxLineLength

    # Validate headers
    $headerLine = ($tableData -split "`n")[0].Trim()
    foreach ($header in $ExpectedHeaders) {
        if ($headerLine -notmatch $header) {
            Should -Fail -Because "Missing expected header: $header"
            return $false
        }
    }

    # Check column alignment
    $lines = $tableData -split "`n" | Where-Object { $_.Trim() }
    $headerPositions = @{}
    
    # Get header positions
    foreach ($header in $ExpectedHeaders) {
        $headerPos = $headerLine.IndexOf($header)
        if ($headerPos -eq -1) {
            Should -Fail -Because "Cannot find header position for: $header"
            return $false
        }
        $headerPositions[$header] = $headerPos
    }

    # Validate data alignment
    for ($i = 2; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        foreach ($header in $ExpectedHeaders) {
            $expectedPos = $headerPositions[$header]
            $columnData = $line.Substring($expectedPos).Split(' ')[0]
            
            # Check if data starts within tolerance
            $actualPos = $line.IndexOf($columnData)
            $alignment = [Math]::Abs($actualPos - $expectedPos)
            
            if ($alignment -gt $FormatOptions.AlignmentTolerance) {
                Should -Fail -Because "Column alignment error for $header. Expected: $expectedPos, Actual: $actualPos"
                return $false
            }
        }
    }

    # Validate line length
    foreach ($line in $lines) {
        if ($line.Length -gt $FormatOptions.MaxLineLength) {
            Should -Fail -Because "Line exceeds maximum length: $($line.Length) > $($FormatOptions.MaxLineLength)"
            return $false
        }
    }

    return $true
}

function Test-ListOutput {
    <#
    .SYNOPSIS
        Tests if the cmdlet output is correctly formatted as a PowerShell list.
    .DESCRIPTION
        Validates PowerShell list output format including property alignment,
        value formatting, and hierarchical display of nested objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Output,

        [Parameter(Mandatory)]
        [string[]]$ExpectedProperties,

        [Parameter()]
        [hashtable]$FormatOptions = $FormatValidationRules
    )

    # Validate output is list format
    if (-not ($Output | Get-Member | Where-Object { $_.MemberType -eq 'MemberSet' -and $_.Name -eq 'FormatStartData' })) {
        Should -Fail -Because "Output is not in list format"
        return $false
    }

    # Convert to string for analysis
    $listData = $Output | Format-List | Out-String

    # Validate properties exist
    foreach ($property in $ExpectedProperties) {
        if ($listData -notmatch "^${property}\s*:") {
            Should -Fail -Because "Missing expected property: $property"
            return $false
        }
    }

    # Check property alignment
    $lines = $listData -split "`n" | Where-Object { $_.Trim() }
    $propertyPosition = -1

    foreach ($line in $lines) {
        if ($line -match "^(\s*)(\w+)\s*:") {
            $indent = $matches[1].Length
            
            # Check consistent property alignment
            if ($propertyPosition -eq -1) {
                $propertyPosition = $indent
            }
            elseif ($indent -ne $propertyPosition) {
                Should -Fail -Because "Inconsistent property alignment. Expected: $propertyPosition spaces, Found: $indent spaces"
                return $false
            }
        }
    }

    # Validate nested object indentation
    $currentIndent = 0
    foreach ($line in $lines) {
        if ($line -match "^(\s*)(\w+)\s*:") {
            $indent = $matches[1].Length
            
            # Check indentation is multiple of specified spaces
            if ($indent % $FormatOptions.IndentationSpaces -ne 0) {
                Should -Fail -Because "Invalid indentation: $indent spaces"
                return $false
            }

            # Validate nested level changes
            $indentChange = $indent - $currentIndent
            if ([Math]::Abs($indentChange) -gt $FormatOptions.IndentationSpaces) {
                Should -Fail -Because "Invalid indentation change: $indentChange spaces"
                return $false
            }
            $currentIndent = $indent
        }
    }

    return $true
}

function Test-RawJsonOutput {
    <#
    .SYNOPSIS
        Tests if the cmdlet output is valid JSON when using raw format.
    .DESCRIPTION
        Validates raw JSON output including schema validation, structure verification,
        and proper encoding of special characters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Output,

        [Parameter(Mandatory)]
        [object]$ExpectedSchema,

        [Parameter()]
        [hashtable]$ValidationOptions = @{
            ValidateSchema = $true
            AllowExtraProperties = $false
            ValidateTypes = $true
        }
    )

    # Validate output can be converted to JSON
    try {
        $jsonString = $Output | ConvertTo-Json -Depth 10
        $jsonObject = $jsonString | ConvertFrom-Json
    }
    catch {
        Should -Fail -Because "Invalid JSON output: $_"
        return $false
    }

    # Validate against schema if specified
    if ($ValidationOptions.ValidateSchema) {
        foreach ($property in $ExpectedSchema.PSObject.Properties) {
            # Check required properties exist
            if (-not $jsonObject.PSObject.Properties[$property.Name]) {
                Should -Fail -Because "Missing required property: $($property.Name)"
                return $false
            }

            # Validate property types if enabled
            if ($ValidationOptions.ValidateTypes) {
                $expectedType = $property.Value.GetType()
                $actualType = $jsonObject.($property.Name).GetType()
                
                if ($actualType -ne $expectedType) {
                    Should -Fail -Because "Type mismatch for property $($property.Name). Expected: $expectedType, Actual: $actualType"
                    return $false
                }
            }
        }
    }

    # Check for extra properties if not allowed
    if (-not $ValidationOptions.AllowExtraProperties) {
        foreach ($property in $jsonObject.PSObject.Properties) {
            if (-not $ExpectedSchema.PSObject.Properties[$property.Name]) {
                Should -Fail -Because "Unexpected property found: $($property.Name)"
                return $false
            }
        }
    }

    return $true
}

function Test-PrettyPrintOutput {
    <#
    .SYNOPSIS
        Tests if the cmdlet output is correctly pretty-printed.
    .DESCRIPTION
        Validates pretty-printed output format including proper indentation,
        line breaks, and formatting of nested objects and arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Output,

        [Parameter()]
        [hashtable]$FormatOptions = $FormatValidationRules
    )

    # Convert output to string for analysis
    $prettyOutput = $Output | ConvertTo-Json -Depth 10

    # Validate JSON structure
    try {
        $null = $prettyOutput | ConvertFrom-Json
    }
    catch {
        Should -Fail -Because "Invalid JSON structure: $_"
        return $false
    }

    # Split into lines for detailed analysis
    $lines = $prettyOutput -split "`n"

    # Track indentation level
    $currentIndent = 0
    $bracketStack = @()

    foreach ($line in $lines) {
        $trimmedLine = $line.TrimStart()
        $lineIndent = $line.Length - $trimmedLine.Length

        # Validate indentation is multiple of specified spaces
        if ($lineIndent % $FormatOptions.IndentationSpaces -ne 0) {
            Should -Fail -Because "Invalid indentation: $lineIndent spaces"
            return $false
        }

        # Check opening/closing brackets
        if ($trimmedLine -match '[\{\[]') {
            $bracketStack += $trimmedLine[0]
            $currentIndent += $FormatOptions.IndentationSpaces
        }
        elseif ($trimmedLine -match '[\}\]]') {
            $currentIndent -= $FormatOptions.IndentationSpaces
            if ($bracketStack.Count -eq 0) {
                Should -Fail -Because "Unmatched closing bracket"
                return $false
            }
            $lastBracket = $bracketStack[-1]
            $bracketStack = $bracketStack[0..($bracketStack.Count - 2)]
            
            # Validate matching brackets
            $expectedClosing = if ($lastBracket -eq '{') { '}' } else { ']' }
            if ($trimmedLine[0] -ne $expectedClosing) {
                Should -Fail -Because "Mismatched brackets: Expected $expectedClosing, found $($trimmedLine[0])"
                return $false
            }
        }

        # Validate line length
        if ($line.Length -gt $FormatOptions.MaxLineLength) {
            Should -Fail -Because "Line exceeds maximum length: $($line.Length) > $($FormatOptions.MaxLineLength)"
            return $false
        }
    }

    # Validate all brackets are closed
    if ($bracketStack.Count -gt 0) {
        Should -Fail -Because "Unclosed brackets: $($bracketStack -join '')"
        return $false
    }

    return $true
}

# Export functions
Export-ModuleMember -Function @(
    'Test-TableOutput',
    'Test-ListOutput',
    'Test-RawJsonOutput',
    'Test-PrettyPrintOutput'
)