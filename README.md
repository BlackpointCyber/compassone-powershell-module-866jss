# PSCompassOne

[![Build Status](https://github.com/blackpoint/pscompassone/workflows/CI/badge.svg)](https://github.com/blackpoint/pscompassone/actions)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)
[![License](https://img.shields.io/github/license/blackpoint/pscompassone)](LICENSE)
[![PowerShell Compatibility](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue)](https://github.com/PowerShell/PowerShell)

PSCompassOne is a PowerShell module that enables seamless programmatic interaction with Blackpoint's CompassOne cyber security platform through its REST API. This module provides native PowerShell integration capabilities, allowing security teams and IT administrators to automate CompassOne operations using familiar PowerShell commands and patterns.

## Overview

PSCompassOne complements existing Node.js and Python SDKs by expanding CompassOne's integration options to better serve Windows-centric environments and PowerShell practitioners. The module significantly reduces implementation time and complexity for organizations leveraging PowerShell automation while ensuring consistent interaction patterns and best practices when working with the CompassOne API.

## Features

- Complete CRUD operations for all CRAFT service objects:
  - Assets management (devices, containers)
  - Findings tracking (alerts, events)
  - Incident management
  - Relationship mapping
  - Tag operations
- Secure credential management through Microsoft.PowerShell.SecretStore
- Cross-platform compatibility with PowerShell 5.1 and 7.x support
- Enterprise-ready deployment options with internal repository support
- Comprehensive error handling with detailed messages and logging
- Flexible output formatting with table, list, and JSON options
- Pipeline support for bulk operations and automation
- Extensive documentation and examples for all commands

## Requirements

- PowerShell 5.1+ (Windows) or PowerShell 7.x (Cross-platform)
- Microsoft.PowerShell.SecretStore module (v1.0.6+)
- Valid CompassOne API credentials
- Network access to CompassOne API endpoints
- TLS 1.2+ support for secure communication

## Installation

### PowerShell Gallery (Recommended)

```powershell
Install-Module -Name PSCompassOne -Scope CurrentUser
```

### Manual Installation

1. Download the latest release from the [GitHub Releases](https://github.com/blackpoint/pscompassone/releases) page
2. Extract the package to a PowerShell module directory:
   - Current user: `$HOME\Documents\WindowsPowerShell\Modules\PSCompassOne`
   - All users: `$env:ProgramFiles\WindowsPowerShell\Modules\PSCompassOne`

### Enterprise Deployment

For enterprise environments, deploy via internal PowerShell repository:

```powershell
Register-PSRepository -Name 'Internal' -SourceLocation 'https://internal.repository.url'
Install-Module -Name PSCompassOne -Repository 'Internal'
```

### Offline Installation

For air-gapped environments:
1. Download the module package on a connected system
2. Transfer the package to the air-gapped system
3. Use `Install-Module` with the `-Source` parameter pointing to the local package

## Quick Start

1. Install the module and dependencies:
```powershell
Install-Module -Name Microsoft.PowerShell.SecretStore
Install-Module -Name PSCompassOne
```

2. Configure SecretStore and store credentials:
```powershell
Initialize-SecretStore
Set-CraftConfiguration -Url "https://api.compassone.com" -Token "your-api-token"
```

3. Basic usage examples:

List assets:
```powershell
Get-CraftAssetList -PageSize 50
```

Get asset details:
```powershell
Get-CraftAsset -Id "asset-uuid"
```

Create new asset:
```powershell
$assetJson = @{
    assetClass = "DEVICE"
    name = "NewServer"
    accountId = "acc123"
    customerId = "cust456"
} | ConvertTo-Json

New-CraftAsset -JsonBody $assetJson
```

Pipeline operations:
```powershell
Get-CraftAssetList | Where-Object { $_.status -eq 'inactive' } | Remove-CraftAsset
```

## Documentation

Detailed documentation is available through PowerShell's built-in help system:

```powershell
Get-Help about_PSCompassOne
Get-Help Get-CraftAsset -Full
Get-Help New-CraftIncident -Examples
```

For additional documentation:
- [Command Reference](docs/commands.md)
- [Usage Examples](docs/examples.md)
- [Error Handling Guide](docs/error-handling.md)
- [Security Best Practices](docs/security.md)
- [Enterprise Deployment Guide](docs/enterprise-deployment.md)

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:
- Development environment setup
- Coding standards
- Pull request process
- Testing requirements

## Security

For security-related information and vulnerability reporting procedures, please refer to our [Security Policy](SECURITY.md).

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Code of Conduct

Please review our [Code of Conduct](CODE_OF_CONDUCT.md) for guidelines on community interaction and expectations.