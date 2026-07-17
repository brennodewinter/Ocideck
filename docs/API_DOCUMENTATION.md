# OciDeck — API Documentation

This document provides comprehensive documentation of the key APIs and interfaces used in the OciDeck codebase.

## Overview

OciDeck follows a modular architecture with well-defined APIs between components. This documentation covers the primary service interfaces, data models, and extension points that are available for developers who want to extend or integrate with OciDeck.

## Core Data Models API

### Deck Model
The `Deck` class represents a complete presentation:
- Metadata (title, author, organization, description)
- Slide list (`List<Slide>`)  
- Theme profile information
- TLP classification level
- User notes and annotations
- Presentation timing targets

### Slide Model
Slides are immutable value objects with typed fields:

```dart
class Slide {
  final String id;
  final SlideType type;
  final Map<String, dynamic> fields; // Type-specific fields based on slide type
}
```

Slide types include: title, section, bullets, two-bullets, split, quote, video, table, code, chart, cockpit, question, timeline, finding, findings-summary, checklist, scope-matrix, sign-off.

### ThemeProfile Model  
Manages visual styling:
- Colors (background, text, accent, etc.)
- Fonts and font families
- Logo configuration
- Footer settings
- Slide-specific overrides

## Key Service Interfaces

### MarkdownService
Handles serialization and parsing of Marp Markdown with OciDeck extensions:

```dart
class MarkdownService {
  // Generate Marp Markdown from Deck model
  String generateDeck(Deck deck);
  
  // Parse Marp Markdown back into Deck model  
  Deck parseDeck(String markdown);
  
  // Validate Markdown structure before editing
  MarkdownValidationResult validateMarkdown(String markdown);
}
```

### ExportService
Main export functionality for PDF, PPTX, and HTML:

```dart
class ExportService {
  // Generate export in requested format
  Future<Uint8List> export(ExportBundle bundle, ExportFormat format);
  
  // Build metadata for exports
  ExportDocumentMetadata buildExportMetadata(Deck deck);
}
```

### PrivacyProjection API
Enforces privacy restrictions across all rendering/export operations:

```dart
class PrivacyProjection {
  // Apply redaction and classification to content
  AudienceDeck projectForAudience(Deck sourceDeck, PrivacyDisposition disposition);
  
  // Validate export against privacy rules
  bool canExportWithPrivacy(AudienceDeck deck, ExportPolicy policy);
}
```

### Git Integration API

```dart
class GitForge {
  Future<List<GitFile>> listTree(String repositoryPath, String path);
  Future<String> readBlob(String repositoryPath, String filePath);  
  Future<String> headSha(String repositoryPath, String branch);
}
```

## Riverpod State Management APIs

### DeckProvider
Manages deck state and history:

```dart
class DeckNotifier extends Notifier<DeckState> {
  // Load a deck from file 
  void loadFromFile(String path);
  
  // Save current deck
  Future<void> save();
  
  // Undo/redo operations
  void undo(); 
  void redo();
}
```

### SettingsProvider  
Handles application configuration:

```dart
class SettingsNotifier extends Notifier<SettingsState> {
  // Update theme profile
  void updateThemeProfile(ThemeProfile profile);
  
  // Set TLP levels and classification policies
  void setClassificationPolicy(ClassificationEnforcementPolicy policy);
}
```

## Extension Points

### Slide Type Extensions
New slide types can be implemented by:
1. Adding to `SlideType` enum 
2. Implementing a corresponding editor widget
3. Adding preview rendering logic
4. Defining serialization format in MarkdownService

### Service Layer Extensibility  
Services follow dependency injection patterns for easy replacement:

```dart
// Example of service interface
abstract class ImageService {
  Future<String> validateAndStoreImage(File file);
  Future<ImageMetadata> getMetadata(String imagePath); 
}
```

## Utility APIs

### NetGuard
Network security enforcement:
- SSRF protection for all outbound requests  
- Address pinning and validation
- Redirect prevention
- Byte caps on transfers

### Asset Path Security
Path validation against project containment rules:

```dart
class ProjectPathValidator {
  bool isWithinProject(String filePath, String projectRoot);
  String sanitizeAssetPath(String path, String projectDir);
}
```

## Authentication and Security APIs

### SecretStore
Secure credential management:
- OS keychain integration (macOS Keychain, Windows Credential Manager)
- Encrypted storage for sensitive information
- API for credential retrieval and storage

### ClassificationEnforcementPolicy
Export security gates:

```dart
class ClassificationEnforcementPolicy {
  bool canExport(Deck deck, ExportSettings settings);
  List<String> getViolations(Deck deck, ExportSettings settings);
}
```

## Web-Specific APIs

### WebAssetStore
In-memory asset storage for web builds:
- Temporary file handling
- Browser-compatible cache management  
- Memory-limited caching strategy

### FetchProxy API (Web Only)
Server-side proxy for CORS issues:

```dart
class FetchProxyService {
  Future<Uint8List> fetchFromUrl(String url);
}
```

## Testing APIs

### Golden Test Framework 
Visual regression testing:
- Slide preview rendering validation  
- Consistent PNG output generation
- Automated visual comparison tools

### Mock Service Interface
For test isolation:
```dart
// Example mock interface for services in tests
class MockMarkdownService implements MarkdownService {
  // Implementation that provides controlled test data
}
```

## Version Compatibility Notes

The API is designed to maintain backward compatibility where possible. Major version changes will be clearly documented with migration paths.

## Future Extension Points

The architecture supports additional extension points including:
- Custom slide types via plugin system  
- Alternative export formats
- Additional authentication methods
- Cloud synchronization services