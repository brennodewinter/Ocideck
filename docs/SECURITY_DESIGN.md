# OciDeck — Security Design

This document outlines the security design principles and mechanisms that protect OciDeck's architecture, data handling, and user privacy.

## Overview

OciDeck follows a strong client-side security model with no application backend. The entire app runs locally on the user's machine (desktop) or browser tab (web), ensuring that presentation content never leaves the device during editing, previewing, presenting, or exporting activities.

## Core Security Principles

### 1. Zero Trust Architecture
- Every component assumes untrusted inputs
- All external data is validated and sanitized before use
- No implicit trust in any network requests or file imports
- External dependencies are carefully vetted for security compliance

### 2. Data Protection at Rest and in Transit
- All user data (presentations, assets, settings) remains local unless explicitly shared
- Sensitive information like credentials is stored securely using OS keychain services
- No telemetry, analytics, or tracking of any kind
- No network communication except for explicit user-initiated actions

### 3. Secure Data Flow
All data flows through clearly defined security gates:
- Asset paths are confined to project folders
- Network requests must pass through `NetGuard` 
- External content is reviewed and sanitized before processing
- Export operations enforce classification policies

## Security Mechanisms

### Network Security (NetGuard)
All outbound network connections funnel through `utils/net_guard.dart`. This system enforces:

1. **SSRF Protection**: Rejects internal targets (loopback, RFC1918, link-local, cloud metadata, CGNAT, ULA, IPv4-in-IPv6) 
2. **Address Pinning**: Socket connections are pinned to validated addresses
3. **Redirect Prevention**: No redirects allowed for security-critical requests
4. **Byte Cap**: Hard limit on data transfer size

### Asset Path Security
All asset references (images, videos, etc.) are resolved within the project folder structure only:
- Absolute paths and `../` escapes are ignored during preview/present/export
- Assets outside the project directory cannot be accessed by decks from untrusted sources
- Project containment is enforced at multiple levels in the system

### Privacy Protection (OciWacht)
The privacy scanning functionality implements:

1. **Data Discovery**: Scans for personal data patterns including:
   - Email addresses
   - Phone numbers  
   - IBAN/Bank account numbers
   - BSN/National ID numbers
   - Address information and postcodes
   - Personal names in various formats

2. **Redaction System**:
   - Double square bracket markers `[[...]]` for manual redaction
   - Automated detection with optional redaction based on rules
   - WYSIWYG rendering that preserves privacy in all export formats

3. **Classification Enforcement**:
   - TLP (Traffic Light Protocol) levels for content classification  
   - Export gate enforcement at the policy level
   - Session-only handling of interactive elements like question slides

### Data Handling and Storage

#### Temporary Files and Recovery
- Auto-save snapshots are stored in a secure temporary location
- Crash recovery data is encrypted where possible 
- All temporary files are automatically cleaned up on exit

#### Settings and Credentials
- User settings are stored locally with encryption when required
- WebDAV credentials, API keys, and other sensitive information are stored using OS keychain services (macOS Keychain, Windows Credential Manager)
- Configuration files never contain raw passwords or tokens

### Export Security

All export operations follow strict security protocols:

1. **Classification Gate**: Enforced before any export is generated
2. **Content Sanitization**: Removes potentially unsafe HTML/JS content in exports
3. **Document Integrity**: Ensures exported documents maintain their integrity (PDF signatures, metadata)
4. **Privacy Projection**: All sensitive data is properly redacted or removed from exports

## Attack Surface Mitigation

### Client-Side Only Approach
- No web backend means no server-side attack surface
- No persistent user tracking or telemetry
- All processing happens in the isolated application environment

### Input Validation and Sanitization
- Markdown parsing with structural pre-flight validation 
- Asset reference validation against project containment rules
- Network request sanitization through NetGuard
- HTML export sanitization to prevent XSS attacks

### Memory Protection
- Images are loaded with memory limits to prevent out-of-memory issues  
- Assets are cached safely without exposing sensitive data
- Temporary files are managed securely and cleared appropriately

## Third-Party Dependencies Security

All dependencies undergo:

1. **License Compliance**: All packages must use recognized open-source licenses (MIT, BSD, Apache2, etc.)
2. **Vulnerability Scanning**: Regular checks for known vulnerabilities in dependencies 
3. **Security Review**: Critical components are reviewed for security implications
4. **Bundled Assets**: JavaScript and other bundled assets have integrity verification

## Compliance and Standards

OciDeck aligns with the following security standards:

- **EU Cyber Resilience Act (CRA)**: Provides SBOM documentation in required formats 
- **GDPR**: Data protection through minimal data collection and privacy controls
- **ISO/IEC 27001**: Risk management principles in design

## Threat Model

### Assumptions
- User's machine is not compromised by malware (assumes trusted environment)
- Network connections are secure, but not inherently trusted
- External files from untrusted sources are carefully reviewed before use

### Potential Attack Vectors
1. **Malicious File Import**: Files with embedded malicious code or data
2. **Network-based Attacks**: Attempts to exploit network components  
3. **Social Engineering**: Tricks targeting user behavior (e.g., phishing links)
4. **Insider Threats**: Malicious actions by users with access to their own files

### Mitigations 
- All file imports are scanned through security gates
- Network requests are strictly controlled and validated
- Input validation prevents injection attacks
- Privacy scanning helps detect sensitive information exposure

## Future Security Enhancements

Planned improvements include:
1. Enhanced encryption for package exports (`.ocideck` files)
2. More granular privacy controls in export settings  
3. Advanced threat detection capabilities
4. Additional security testing and verification procedures