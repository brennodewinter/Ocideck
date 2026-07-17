# OciDeck — Migration Guide

This document provides guidance for migrating between different versions of OciDeck, including breaking changes and recommended procedures.

## Overview

OciDeck follows semantic versioning to help users understand the impact of updates. This guide outlines migration paths from previous versions to newer ones, helping maintain continuity in workflows while adopting new features.

> **Status:** OciDeck is **pre-release (currently 0.2.0) and has no formal
> versioning or release scheme yet** — there are no numbered releases to migrate
> between today. The version-specific sections below are **illustrative
> placeholders** showing the shape of the migration notes real releases will
> carry once versioning begins (breaking-change summary, migration steps,
> rollback). Treat the "1.x/2.x/3.x" headings as examples of the format, not as
> versions that exist. This guide will be rewritten with concrete steps when the
> project adopts a release scheme.

## Version 1.x to 2.x Migration (illustrative — no such release exists)

### Breaking Changes

#### File Format Updates
- Updated Markdown format with enhanced TLP handling
- New privacy disposition fields in front matter  
- Enhanced classification enforcement policies
- Updated `.ocideckstyle` file format (version 2.0)

#### API Changes
- `MarkdownService` interface modifications for better error handling
- Changed `ExportBundle` structure to support new audience profiles
- Updated privacy projection APIs with stricter enforcement

### Migration Steps

1. **Backup All Presentations**: Create backups of all decks before updating
2. **Update Dependencies**: Ensure Flutter/Dart toolchain matches requirements  
3. **Test Import Process**: Open a few sample decks in the new version to verify compatibility
4. **Review TLP Settings**: Re-examine deck classification levels as enforcement has been strengthened
5. **Verify Privacy Settings**: Check that privacy disposition settings are properly applied

## Version 2.x to 3.x Migration (illustrative — no such release exists)

### Breaking Changes

#### Security Enhancements
- New stricter network security gates (NetGuard)
- Enhanced privacy scanning with new redaction options  
- Updated classification enforcement policies
- Improved asset path containment rules

#### Feature Removals and Additions
- Removed legacy slide types that were rarely used
- Added support for new chart visualizations 
- Enhanced AI integration capabilities

### Migration Steps

1. **Review Security Settings**: Update any security configurations to match new requirements  
2. **Test Network Access**: Verify that external URL imports still work correctly with new restrictions
3. **Update Privacy Policies**: Review and update privacy classification policies
4. **Validate Export Settings**: Test all export operations, especially those involving sensitive content

## Migration Best Practices

### Before Updating
1. **Create Comprehensive Backups**:
   - Backup all presentation files (.md)
   - Save custom theme profiles (`.ocideckstyle`)  
   - Document any custom configurations or workflows
2. **Review Current Version**: Note current version and configuration settings
3. **Test Environment**: Set up test environment with new version for verification

### During Update Process
1. **Incremental Migration**:
   - Migrate one presentation at a time to verify compatibility
   - Test critical workflow scenarios after each migration  
2. **Validation Testing**:
   - Check that all slides render correctly
   - Verify export functionality works as expected
3. **Feature Verification**: Ensure new features work according to documentation

### After Update Completion
1. **Full Validation Suite**:
   - Run through typical workflows with full presentation testing  
   - Validate privacy and security settings are functioning correctly
2. **Performance Testing**: Check that performance characteristics match expectations
3. **Documentation Update**: Update any internal documentation or processes  

## Handling Specific Issues

### File Format Incompatibilities

If older files don't open properly:
1. Use the "Recover" feature for corrupted files (if available)
2. Manual backup restoration from previous version if needed  
3. Recreate critical presentations using new format specifications
4. Contact support with detailed error information if problems persist

### Security Gate Issues  

When encountering network security restrictions:
- Review NetGuard settings and update configurations as needed
- Configure trusted internal servers properly for WebDAV connections  
- Understand the stricter enforcement of external access policies

### Privacy Enforcement Problems

If privacy enforcement prevents expected functionality:
1. Check TLP classification levels in decks
2. Verify that required permissions are set appropriately  
3. Review privacy disposition settings on slides and decks
4. Consult updated documentation on new privacy features

## Automated Migration Tools

OciDeck provides migration assistance for major version changes:

### File Format Converters
- Automatic conversion of older Markdown format to current specification
- Theme profile migration tools (`.ocideckstyle`)
- Backward compatibility layer for some legacy features

### Configuration Migration
- Settings preservation across versions  
- Automatic cleanup of deprecated configuration options

## Version-Specific Considerations

### For Desktop Users
1. **File System Permissions**: Ensure proper access to project directories after update
2. **Plugin Updates**: Check that vendored plugin forks are compatible with new version
3. **Hardware Compatibility**: Verify system requirements for newer features

### For Web Users  
1. **Browser Requirements**: Confirm browser support for new web APIs
2. **CSP Configuration**: Ensure Content Security Policy settings remain effective
3. **Proxy Setup**: Validate fetch-proxy configuration if using external decks

## Rolling Back to Previous Versions

In case of critical issues:
1. Use versioned backups created before update  
2. Uninstall current version and install previous compatible version
3. Restore from backup files (ensure they are compatible with older version)
4. Document the rollback for future reference  

## Support Resources

For migration assistance or specific issues:
- Community forums and support channels
- Official documentation updates 
- The project's issue tracker (Forgejo) for bug reports
- Release notes detailing breaking changes

## Future Migration Considerations

### Planned Migration Paths
The development team plans to make future migrations smoother by:
1. Providing clearer migration tooling  
2. Maintaining backward compatibility for major features
3. Adding comprehensive auto-conversion tools where possible
4. Documenting breaking changes in advance of releases

This guide will be updated with each version release to reflect current and upcoming migration considerations.