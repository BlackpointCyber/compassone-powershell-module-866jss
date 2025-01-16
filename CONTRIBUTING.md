# Contributing to PSCompassOne

## Introduction

Welcome to the PSCompassOne project! This PowerShell module enables programmatic interaction with Blackpoint's CompassOne cyber security platform. We appreciate your interest in contributing and have established these guidelines to ensure consistent, high-quality contributions.

## Code of Conduct

All contributors are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md). Please read it before participating in this project.

## Getting Started

### Development Environment Setup

1. PowerShell Requirements:
   - PowerShell 5.1 (Windows PowerShell)
   - PowerShell 7.x (Cross-platform)
   - Ensure both versions for cross-platform testing

2. Required Modules:
   ```powershell
   Install-Module -Name Pester -MinimumVersion 5.3.0
   Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.20.0
   Install-Module -Name platyPS -MinimumVersion 2.0.0
   Install-Module -Name Microsoft.PowerShell.SecretStore
   ```

3. Development Tools:
   - Visual Studio Code with PowerShell extension
   - Git for version control
   - Docker for containerized testing (optional)

4. Cross-Platform Setup:
   - Windows: Install both PowerShell versions
   - Linux/macOS: Install PowerShell 7.x
   - Configure line endings (core.autocrlf=true)

## Development Process

### Branch Naming Convention
- Feature branches: `feature/description`
- Bug fixes: `bugfix/issue-number`
- Hotfixes: `hotfix/description`

### Commit Messages
```
type(scope): description

[optional body]

[optional footer]
```
Types: feat, fix, docs, style, refactor, test, chore

### Version Control Workflow
1. Fork the repository
2. Create feature branch
3. Develop and test locally
4. Push changes to fork
5. Submit pull request

## Testing Requirements

### Code Coverage Requirements
- 100% code coverage mandatory
- Both unit and integration tests required
- Cross-platform testing mandatory

### Testing Framework
```powershell
# Pester test structure
Describe 'Feature' {
    Context 'Scenario' {
        It 'Should do something' {
            # Test implementation
        }
    }
}
```

### Test Categories
1. Unit Tests
   - Function-level testing
   - Mocked dependencies
   - Parameter validation

2. Integration Tests
   - API interaction
   - Cross-module functionality
   - Error handling

3. Cross-Platform Tests
   - Windows PowerShell 5.1
   - PowerShell 7.x on all platforms

## Pull Request Process

1. Pre-submission Checklist:
   - [ ] Tests pass on all platforms
   - [ ] 100% code coverage maintained
   - [ ] PSScriptAnalyzer shows no warnings
   - [ ] Documentation updated
   - [ ] Changelog updated

2. PR Template Requirements:
   - Issue reference
   - Change description
   - Testing verification
   - Breaking changes noted

3. Review Process:
   - Two approvals required
   - CI/CD checks must pass
   - Security scan clear

## Coding Standards

### PowerShell Best Practices
1. Command Naming:
   - Use approved verbs
   - PascalCase for nouns
   - Prefix with 'Craft'

2. Code Style:
   ```powershell
   function Verb-CraftNoun {
       [CmdletBinding()]
       param(
           [Parameter(Mandatory)]
           [string]$RequiredParam,
           
           [Parameter()]
           [string]$OptionalParam
       )
       
       begin {
           # Initialization
       }
       
       process {
           # Main logic
       }
       
       end {
           # Cleanup
       }
   }
   ```

3. Documentation:
   - Comment-based help
   - Parameter descriptions
   - Examples included
   - XML documentation for classes

### Error Handling
```powershell
try {
    # Operation
}
catch [System.Net.WebException] {
    Write-Error -Exception $_ -Category ConnectionError
}
catch {
    Write-Error -Exception $_ -Category OperationStopped
}
```

## Security Guidelines

1. Credential Handling:
   - Use SecretStore for credential storage
   - Never log sensitive data
   - Secure string for passwords

2. Security Best Practices:
   - Input validation
   - TLS 1.2+ enforcement
   - Principle of least privilege

3. Vulnerability Reporting:
   - Use GitHub Security Advisories
   - Include reproduction steps
   - Maintain confidentiality

## Release Process

### Version Numbering (SemVer)
- Major.Minor.Patch
- Breaking changes increment Major
- New features increment Minor
- Fixes increment Patch

### Release Checklist
1. Version Update:
   - Module manifest
   - Documentation
   - Changelog

2. Verification:
   - Full test suite
   - Cross-platform validation
   - Security scan

3. Publishing:
   - Sign module
   - Update PowerShell Gallery
   - Create GitHub release

## Troubleshooting

### Common Issues
1. Build Failures:
   - Check PowerShell versions
   - Verify module dependencies
   - Review test logs

2. Test Failures:
   - Check platform compatibility
   - Verify mocked dependencies
   - Review code coverage

### Support Resources
- GitHub Issues
- Project Documentation
- Community Discussions

For additional assistance, please open an issue or join our community discussions.