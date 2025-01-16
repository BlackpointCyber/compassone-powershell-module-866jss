# Changelog
All notable changes to PSCompassOne will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial module structure and core components
- Basic CRAFT service object support (assets, findings, incidents)
- SecretStore integration for credential management

### Changed
- None

### Deprecated
- None

### Removed
- None

### Fixed
- None

### Security
- Implemented secure credential handling via Microsoft.PowerShell.SecretStore
- TLS 1.2+ enforcement for API communications

### PowerShell Compatibility
- Minimum version: PowerShell 5.1
- Tested versions: 5.1, 7.2, 7.3
- Platform support: Windows PowerShell 5.1, PowerShell 7.x (Windows, Linux, macOS)

### API Compatibility
- Minimum API version: v1.0
- Tested versions: v1.0
- Breaking changes: None (initial release)

## [0.1.0] - 2024-01-20

### Added
- Core module framework
- Basic CompassOne API client implementation
- Asset management cmdlets (Get-CraftAsset, Get-CraftAssetList)
- Finding management cmdlets (Get-CraftFinding, Get-CraftFindingList)
- Incident management cmdlets (Get-CraftIncident, Get-CraftIncidentList)
- Initial PowerShell help documentation
- Basic output formatting for CRAFT objects

### Changed
- None (initial release)

### Deprecated
- None

### Removed
- None

### Fixed
- None

### Security
- Secure credential storage implementation
- API token encryption at rest
- TLS 1.2+ requirement for API communication

### PowerShell Compatibility
- Minimum version: PowerShell 5.1
- Tested versions:
  - Windows PowerShell 5.1
  - PowerShell 7.2
  - PowerShell 7.3
- Platform support:
  - Windows: Full support
  - Linux: PowerShell 7.x only
  - macOS: PowerShell 7.x only

### API Compatibility
- Minimum version: v1.0
- Tested versions:
  - CompassOne API v1.0
- Breaking changes: None (initial release)

[Unreleased]: https://github.com/blackpoint/pscompassone/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/blackpoint/pscompassone/releases/tag/v0.1.0