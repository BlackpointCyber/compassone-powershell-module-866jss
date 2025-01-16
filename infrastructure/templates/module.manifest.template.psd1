@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'PSCompassOne.psm1'

    # Version number of this module.
    ModuleVersion = '__VERSION__'

    # Unique identifier for this module
    GUID = '__GUID__'

    # Author of this module
    Author = '__AUTHOR__'

    # Company or vendor of this module
    CompanyName = '__COMPANY__'

    # Copyright statement for this module
    Copyright = '__COPYRIGHT__'

    # Description of the functionality provided by this module
    Description = '__DESCRIPTION__'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{
            ModuleName = 'Microsoft.PowerShell.SecretStore'
            ModuleVersion = '1.0.6'
        }
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Get-CraftAsset',
        'New-CraftAsset',
        'Set-CraftAsset',
        'Remove-CraftAsset',
        'Get-CraftFinding',
        'New-CraftFinding',
        'Set-CraftFinding',
        'Remove-CraftFinding'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # List of all files packaged with this module
    FileList = @(
        'PSCompassOne.psd1',
        'PSCompassOne.psm1',
        'en-US/about_PSCompassOne.help.txt'
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for PowerShell Gallery discoverability
            Tags = @(
                'CompassOne',
                'Security',
                'API',
                'PSEdition_Desktop',
                'PSEdition_Core',
                'Windows',
                'Linux'
            )

            # Project site URL
            ProjectUri = 'https://github.com/blackpoint/pscompassone'

            # License URI for this module
            LicenseUri = 'https://github.com/blackpoint/pscompassone/blob/main/LICENSE'

            # Release notes URI for this module
            ReleaseNotes = 'https://github.com/blackpoint/pscompassone/blob/main/CHANGELOG.md'
        }
    }
}