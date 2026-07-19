# OciDeck — Troubleshooting Guide

This document provides solutions for common issues and problems users may encounter while using OciDeck.

## Overview

This guide addresses frequently encountered problems, their causes, and step-by-step solutions. It covers both user-facing issues and technical problems that developers or advanced users might experience.

## Common User Issues

### Presentation Files Not Opening

**Symptoms**: 
- Error messages when trying to open deck files
- Blank screens or application crashes on file load  
- "Invalid file format" warnings

**Solutions**:
1. **Check File Integrity**:
   - Verify the .md file isn't corrupted (try opening in a text editor)
   - Ensure proper file extension (.md for standard decks)

2. **File Format Validation**:
   - Confirm the file follows the OciDeck Markdown format specification  
   - Check that front matter is properly formatted with YAML syntax
   - Verify slide separators are correctly formatted (`---` on their own line)

3. **Recovery Options**:
   - Use crash recovery snapshots (automatically generated)
   - Restore from Git repository if available
   - Try opening backup copies

### Export Problems

**Symptoms**:
- Exports fail or produce corrupted files  
- Missing content in exported documents
- Error messages during export process

**Solutions**:
1. **Check Classification Settings**:
   - Verify TLP levels aren't blocking exports
   - Confirm privacy disposition settings allow the export  

2. **Memory Management**:
   - Close other applications to free system resources  
   - Break large presentations into smaller chunks if needed
   - Try exporting individual slides instead of full decks

3. **Format-Specific Issues**:
   - For PDF/PPTX: Ensure no complex charts or media causing rendering issues  
   - For HTML: Check network security settings that might block external assets

### Performance Issues

**Symptoms**:
- Slow preview rendering
- Application freezing during editing or presentation
- High memory usage  

**Solutions**:
1. **Optimize Presentation Content**:
   - Reduce number of slides in large presentations  
   - Simplify complex charts (fewer data series)
   - Compress image assets before import

2. **System Resources**:
   - Close other applications to free RAM
   - Check for system updates that might improve performance
   - Consider upgrading hardware if consistently hitting limits

3. **Cache Management**:
   - Clear temporary files when possible  
   - Restart OciDeck to clear memory caches

## Technical Issues

### Network and Security Problems  

**Symptoms**:
- URL import fails due to CORS restrictions
- WebDAV connection issues
- Privacy scan flags false positives  

**Solutions**:
1. **URL Import Restrictions**:
   - Use the fetch-proxy server for external decks that don't support CORS  
   - Check network connectivity and firewall settings

2. **WebDAV Configuration**:
   - Verify credentials are correct in Settings
   - Check the server type: on *Nextcloud or ownCloud* the DAV path is derived
     from the host, so a path in the server URL is ignored; on *Other WebDAV
     server* that path is the WebDAV root and a missing one is a common cause
     of "folder not found"
   - Ensure trusted internal server is set appropriately if using local addresses
   - Test connection before saving to verify configuration works  

3. **Privacy Scan Issues**:
   - Review privacy disposition settings for the deck/individual slides  
   - Check that redaction markers are properly formatted (`[[...]]`)
   - Adjust sensitivity thresholds in security preferences

### Installation and Setup Problems

**Symptoms**:
- Application fails to start or crashes on launch
- Missing dependencies or library errors
- Platform-specific issues  

**Solutions**:
1. **Verify Prerequisites**:
   - Check Flutter/Dart version requirements match installed versions  
   - Confirm platform toolchain is properly configured
   - Ensure sufficient disk space for installation

2. **Reinstallation Process**:
   - Completely uninstall OciDeck before reinstalling
   - Clear any residual configuration files in application directories  
   - Reinstall with clean dependencies using `make setup`

3. **Platform-Specific Issues**:
   - macOS: Verify Xcode command line tools are installed
   - Windows: Ensure Visual Studio development workload is enabled
   - Linux: Confirm GTK/Clang/Ninja dependencies

## Advanced Troubleshooting

### Debugging Tools and Logs

1. **Application Logging**: 
   - Enable verbose logging in preferences for detailed diagnostics  
   - Check application logs in system console or log files

2. **Error Analysis**:
   - Capture error messages with stack traces when possible
   - Note exact steps that trigger the problem
   - Document environment details (OS version, Flutter version)

### Development Environment Issues  

**Symptoms**:
- Build failures during development  
- Test suite failing in local environment
- Debugging problems

**Solutions**:
1. **Environment Verification**:
   - Run `make check` to verify all quality gates pass locally
   - Ensure toolchain versions match project requirements (Flutter 3.44.6)
   - Verify dependencies are correctly installed (`flutter pub get`) 

2. **Testing Environment**:
   - Use consistent development environment across team members
   - Validate that test cases work in both desktop and web builds  
   - Check for platform-specific testing requirements

## System Integration Issues

### Git Repository Problems  

1. **Repository Access Failures**:
   - Verify repository URL is correct and accessible
   - Confirm authentication credentials are properly configured  
   - Check network connectivity to git server

2. **Branch/Tag Management**: 
   - Ensure branch names match expectations in configuration
   - Verify that release tags haven't been moved or deleted

### File System Integration  

1. **Path Resolution Issues**:
   - Confirm project directories are accessible and properly configured  
   - Check for permissions issues with asset directories
   - Verify absolute paths aren't being used when relative should be

## Known Issues and Workarounds

### Current Limitations

1. **Web Build Constraints**:
   - Limited memory capacity compared to desktop version  
   - Browser-specific rendering differences
   - No native filesystem access for web builds  

2. **Performance with Large Media**:
   - Very large video files may cause browser instability on web builds
   - Memory-intensive operations can impact responsiveness

### Temporary Workarounds

1. **For Export Issues**: 
   - Try different export formats if one fails
   - Simplify presentation content before exporting
   - Use smaller segments for very large decks  

2. **For Network Problems**:
   - Configure fetch-proxy server when CORS restrictions prevent direct access  
   - Test external connections separately to isolate issues

## Diagnostic Procedures

### System Information Collection

1. **Basic Info Gathering**:
   - Note OciDeck version, OS version, and Flutter/Dart versions
   - Capture exact error messages with timestamps  
   - Document steps taken before the issue occurred

2. **Diagnostic Testing**:
   - Try reproduction on different files or systems if possible
   - Test against a known good baseline (working deck)
   - Isolate variables to identify specific problem conditions  

### Reporting Issues Effectively

When submitting bug reports or support requests:

1. Include complete error messages and stack traces  
2. Provide step-by-step instructions to reproduce the issue
3. Attach relevant configuration files if possible
4. Mention system specifications and environment details
5. Specify whether the problem occurs with all files or just specific ones

## Community Resources

### Support Channels

1. **Official Forums**: 
   - User discussion board for general questions
   - Developer discussions for technical issues  

2. **Documentation Sources**:
   - Official API documentation  
   - Troubleshooting articles and guides
   - Release notes with known issue tracking

3. **Community Help**:
   - Peer support through user groups or communities  
   - Contributing guidelines for reporting bugs effectively

## Prevention Best Practices

### Regular Maintenance

1. **System Updates**: 
   - Keep OciDeck updated to latest stable version
   - Apply system and toolchain updates regularly  

2. **Backup Strategies**:
   - Implement regular backup of important presentations
   - Test backup restoration procedures periodically
   - Maintain multiple versions for recovery scenarios

3. **Performance Monitoring**:  
   - Monitor application performance over time
   - Address issues before they become critical problems
   - Optimize presentation content proactively  

## When to Seek Professional Help

### Escalation Path

1. **Simple Issues**:
   - Try troubleshooting steps in this guide first
   - Check documentation and FAQs for known solutions  

2. **Complex Problems**:  
   - If issues persist after standard troubleshooting
   - For systematic or recurring problems across multiple files/instances
   - When performance degradation indicates deeper system issues

3. **Reporting Bugs**:
   - Submit detailed bug reports with reproduction steps
   - Include relevant logs and environment information  
   - Follow project contribution guidelines for issue tracking

This guide should help users resolve most common problems they encounter while using OciDeck. For persistent or complex issues, please consult the official documentation or contact support channels.