# Security Policy

PSCompassOne is committed to maintaining the highest security standards for PowerShell-based interaction with the CompassOne cyber security platform. This document outlines our security policies, supported versions, vulnerability reporting procedures, and security controls.

## Supported Versions

| PowerShell Version | Security Support Status | End of Support Date | Security Features |
|-------------------|------------------------|-------------------|-------------------|
| 7.x (Latest) | Full Support | Current + 2 years | Full SecretStore, Enhanced Error Handling, Cross-Platform Security |
| 7.0 | Security Updates Only | 2024-12-31 | Full SecretStore, Enhanced Error Handling |
| 5.1 | Limited Support | 2025-12-31 | Basic SecretStore, Windows-Only Security Features |
| < 5.1 | Not Supported | Expired | Not Supported |

## Reporting a Vulnerability

We take security vulnerabilities seriously and appreciate the security community's efforts in responsibly disclosing any issues.

### Reporting Process

1. **DO NOT** create public GitHub issues for security vulnerabilities
2. Submit vulnerability reports to security@blackpoint.com
3. Encrypt sensitive information using our [PGP key](https://blackpoint.com/security/pgp-key)

### Required Information

- Detailed description of the vulnerability
- Steps to reproduce the issue
- PowerShell version and environment details
- Any proof-of-concept code (if applicable)
- Impact assessment

### Response Timeline

- Initial Response: Within 24 hours
- Status Update: Within 72 hours
- Fix Timeline: Based on severity
  - Critical: 7 days
  - High: 30 days
  - Medium: 60 days
  - Low: 90 days

## Security Controls

| Control Category | Implementation | Version Added | Validation Method |
|-----------------|----------------|---------------|-------------------|
| Authentication | SecretStore Integration | 1.0.0 | Automated Testing |
| Transport Security | TLS 1.2+ Enforcement | 1.0.0 | Protocol Validation |
| Token Management | AES-256 Encryption | 1.0.0 | Cryptographic Verification |
| Audit Logging | PowerShell Event Log | 1.0.0 | Log Analysis |
| Input Validation | Parameter Validation | 1.0.0 | Schema Validation |
| Output Security | Data Sanitization | 1.0.0 | Security Scanning |

### SecretStore Implementation Example
```powershell
# Initialize secure credential storage
Register-SecretVault -Name PSCompassOneVault -ModuleName Microsoft.PowerShell.SecretStore
Set-Secret -Name CompassOneApiToken -SecureString $secureToken -Vault PSCompassOneVault
```

## Security Best Practices

1. **Credential Management**
   - Always use SecretStore for API token storage
   - Never store credentials in plain text
   - Rotate API tokens regularly

2. **Transport Security**
   - Ensure TLS 1.2+ is enabled
   - Validate SSL/TLS certificates
   - Use secure network connections

3. **Access Control**
   - Follow principle of least privilege
   - Regularly audit access permissions
   - Implement role-based access control

4. **Audit and Logging**
   - Enable PowerShell script logging
   - Monitor security events
   - Maintain audit trails

### Security Configuration Example
```powershell
# Configure secure defaults
$PSCompassOneConfig = @{
    RequireTLS12 = $true
    EnableAuditLogging = $true
    TokenExpirationDays = 30
    MaxRetryAttempts = 3
    SecureOutputMode = $true
}
```

## Security Updates

### Update Distribution

1. Security updates are distributed through:
   - PowerShell Gallery (signed packages)
   - GitHub Releases (signed commits)
   - Emergency hotfix distribution system

### Update Verification

- All security updates include digital signatures
- Package integrity is verified during installation
- Update authenticity can be validated using public keys

### Emergency Updates

- Critical security fixes are fast-tracked
- Emergency notifications sent to registered users
- Hotfix deployment procedures documented in admin guide

## Compliance Requirements

| Requirement | Implementation | Validation | Documentation |
|------------|----------------|------------|---------------|
| Data Encryption | AES-256 | Cryptographic Testing | Security Controls Guide |
| Secure Transport | TLS 1.2+ | Protocol Validation | Integration Guide |
| Access Control | Token-based Auth | Authentication Testing | API Documentation |
| Audit Logging | Event Logging | Log Verification | Compliance Guide |
| Secret Management | SecretStore | Security Review | Implementation Guide |
| Input Validation | Parameter Validation | Test Coverage | Development Guide |

### Compliance Validation

1. Regular security assessments
2. Automated compliance checking
3. Third-party security audits
4. Continuous monitoring
5. Compliance reporting

For additional security information or questions, contact security@blackpoint.com or refer to our [Security Documentation](https://docs.blackpoint.com/security).