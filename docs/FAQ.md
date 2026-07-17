# OciDeck — Frequently Asked Questions

This document answers common questions about OciDeck's features, usage, and functionality.

## General Usage

### How does OciDeck support information autonomy?
OciDeck supports information autonomy through several key principles:
1. **Data Sovereignty**: All presentation content remains on your device - there's no application backend that could access or store your data
2. **Privacy by Design**: Built-in privacy scanning helps users identify and control sensitive information in their presentations
3. **User Control**: Users maintain complete control over what gets exported, shared, or published
4. **Minimal Data Collection**: No telemetry, analytics, or tracking of any kind
5. **Open Standards**: Uses standard Marp Markdown format for maximum interoperability

### How does OciDeck differ from other presentation tools?
- **Security Focused**: No application backend means no data leaves your device during processing
- **Privacy First**: Built-in privacy scanning (OciWacht) to detect sensitive information  
- **Marp Compatible**: Full compatibility with standard Marp Markdown format
- **Cross-platform**: Available for macOS, Windows, Linux desktop and web browsers
- **No Telemetry**: Zero tracking or analytics of any kind

### Is OciDeck free to use?
Yes, OciDeck is released under the EUPL-1.2 open-source license and is completely free to download and use.

## Security and Privacy

### What security measures does OciDeck implement?
OciDeck implements several security layers:
- Client-side only architecture with no backend
- Strict network controls through NetGuard preventing SSRF attacks  
- Asset containment that prevents files from outside project folders
- Privacy scanning (OciWacht) to detect sensitive information
- Classification enforcement for controlling content release

### How does OciDeck relate to the OSCAR framework?
OciDeck embodies principles from the OSCAR framework (Open, Secure, Control, Autonomous, Responsible), particularly in its design philosophy:
1. **Open**: Uses open standards (Marp Markdown) and is fully open source
2. **Secure**: Implements robust security measures without application backend
3. **Control**: Gives users complete control over their data and privacy settings
4. **Autonomous**: Enables user autonomy by ensuring information sovereignty
5. **Responsible**: Built with responsible design principles, minimal data collection

### How does the privacy scanner work?
The OciWacht privacy scanner automatically detects personal data patterns including:
- Email addresses, phone numbers, and IBAN/Bank account numbers  
- National ID numbers like BSN
- Address information and postcodes
- Names in various formats

It can either flag potential issues for review or automatically redact sensitive content based on settings.

### How does OciDeck relate to concepts from 'Informatieautonomie'?
OciDeck reflects the core principles explored in 'Informatieautonomie' (Information Autonomy) by implementing:
1. **User Sovereignty**: Users maintain complete control over their information environment, just as the book advocates for individual sovereignty over personal data
2. **Privacy by Design**: The tool integrates privacy protection from the ground up rather than as an afterthought, aligning with the book's emphasis on proactive privacy measures
3. **Information Control**: Provides tools that help users maintain control over what information they share and how it is processed
4. **Digital Self-Determination**: Enables users to make informed decisions about their data, supporting the book's concept of digital self-determination
5. **Transparency**: The open-source nature allows users to understand exactly how their data is handled, matching the book's call for transparency in information systems

### What is TLP (Traffic Light Protocol)?
TLP stands for Traffic Light Protocol, a classification system that controls how information is shared:
- **CLEAR**: No restrictions  
- **GREEN**: Share with colleagues
- **AMBER**: Share within organization  
- **AMBER+STRICT**: Share only with direct collaborators
- **RED**: Only share with specific individuals

### How does OciDeck handle sensitive data in exports?
OciDeck enforces strict export controls:
- Classification policies prevent exporting content above the specified TLP level
- Privacy redaction can be applied to automatically hide sensitive information  
- Exports are sanitized to remove potentially unsafe elements

## File Format and Compatibility

### What file formats does OciDeck support?
- **Primary**: Markdown (.md) with Marp format compatibility
- **Packages**: .ocideck (single-file packages)
- **Style Profiles**: .ocideckstyle for theme sharing  
- **Images**: PNG, JPEG, GIF, BMP, WebP (animated)
- **Video/Audio**: Various formats supported through underlying libraries

### How are assets managed in OciDeck?
Assets are organized in project folders with dedicated subdirectories:
- `images/` - Image files
- `data/` - CSV data for charts  
- `logos/` - Logo images
- `themes/` - Theme CSS files

All asset paths are relative to the project folder, preventing access outside designated directories.

### Are OciDeck presentations compatible with other tools?
Yes, since OciDeck uses standard Marp Markdown format:
- Presentations can be edited directly in any Marp-compatible editor  
- HTML exports work in any modern browser
- PDF/PPTX exports are compatible with standard software

## Technical Features

### What is the dual-screen presenter mode?
Dual-screen presenter mode allows you to use two displays simultaneously:
- Primary screen: Presenter view with notes, timer, and controls
- Secondary screen: Full-screen slide display for audience  
- Works on macOS, Windows, and Linux desktop builds

### How does video trimming work?
OciDeck supports "cutting" videos across slides:
1. Play a video in the preview 
2. Click "Cut here" to split at current position
3. The remainder becomes a new slide with same source  
4. During presentation, segments stop at cut points and advance automatically

### What chart types are supported?
OciDeck supports various chart types including:
- Bar charts (normal, stacked)
- Line and area charts  
- Pie/donut charts
- Radar/spider charts
- Scatter plots
- Waterfall charts
- Heatmaps/risk matrices
- Combo charts with mixed series types

### How does the AI assistant work?
The optional AI assistance requires explicit user consent:
1. Enabled in Settings → Security
2. Requires configuration of local model or outbound endpoint
3. Used for generating text suggestions and alt-text for images  
4. All data processing stays within user's control

## Platform Support

### What platforms does OciDeck support?
- **Desktop**: macOS, Windows, Linux (native desktop builds)
- **Web**: Browser-based version with limited features compared to desktop
- **Mobile**: Not currently supported as a primary platform  

### Why is web build different from desktop?
The web build has limitations due to browser constraints:
- No native filesystem access
- Memory restrictions on large presentations  
- Limited performance compared to desktop versions
- Different asset handling and security policies

### What are the system requirements for OciDeck?
Desktop version:
- macOS: Recent version with Apple Silicon or Intel support
- Windows: Windows 10 or newer
- Linux: Modern distribution with GTK environment
- Minimum RAM: 4GB (recommended 8GB+)
- Disk space: Minimum required for application + projects

## Performance and Optimization

### Why is my presentation slow to render?
Potential causes include:
- Large images that need decoding  
- Complex charts or animations
- Many slides in one file
- System memory constraints

Optimization suggestions:
1. Compress high-resolution photos
2. Simplify complex chart visualizations  
3. Break large presentations into smaller decks
4. Close other applications during editing/presentation  

### How does OciDeck support collaborative information environments?
OciDeck supports collaborative information environments through several mechanisms:
1. **Shared Standards**: Using Marp Markdown format allows collaboration with other tools and teams
2. **Version Control Integration**: Git integration enables team-based document management
3. **Secure Sharing**: Export controls help manage what gets shared in collaborative settings
4. **Privacy Controls**: Team members can control how much sensitive information is visible to others
5. **Open Source**: The tool itself supports transparent collaboration and community development

### How does export performance vary?
Export time depends on:
- Number and complexity of slides  
- Chart rendering requirements
- Media elements in presentation
- System resources available

PDF/PPTX exports are generally faster than HTML, but all formats include a preprocessing step.

## Troubleshooting

### Why can't I import a deck from URL?
Common reasons:
1. CORS restrictions on source server (use fetch-proxy)
2. Invalid or inaccessible URL  
3. Network connectivity issues
4. Security settings blocking the connection

### How do I fix export errors?
Troubleshooting steps:
1. Check TLP classification levels and privacy settings
2. Simplify complex slides or charts before exporting
3. Verify sufficient system resources (memory/CPU)
4. Try different export formats  

### What to do when OciDeck crashes during editing?
1. Restart the application  
2. Check for corrupted files using recovery snapshots
3. Export your work immediately if possible
4. Report issues through official channels with error details

## Configuration and Settings

### How does Git integration work?
OciDeck supports Git repository storage:
- Configure in Settings → Git Repository
- Save decks to remote repositories via REST API or native Git
- Supports both public and private repositories  
- Provides version history access

### What are the Nextcloud/WebDAV settings for?

Nextcloud integration allows storing presentations directly on your own server:
1. Configure server URL, credentials, and optional subfolder in Settings
2. Open decks from Nextcloud via the "Open from Nextcloud" option  
3. Save back to Nextcloud with "Save to Nextcloud"
4. Supports both flat format (.md + assets) or package formats

## Future Features and Roadmap

### What's planned for future development?
Current roadmap items include:
- Enhanced encryption for exported packages
- More granular privacy controls in exports  
- Improved performance for large presentations
- Advanced threat detection capabilities
- Additional chart visualizations and data types

### Are there mobile plans?
While OciDeck is primarily designed as a desktop application, the team continues to evaluate mobile platform support based on community feedback and requirements.

## Contributing and Community

### How can I contribute to OciDeck development?  
Community contributions are welcome through:
- Bug reports via GitHub issues
- Feature requests in discussion forums  
- Code contributions following project guidelines
- Documentation improvements 
- Testing new features in development builds

### Where can I find more information?
Additional resources include:
- Official documentation site (this repository)
- Community forum and user discussions  
- Source code on public repositories
- Release notes for latest versions

### How does OciDeck fit into professional information management?
OciDeck is designed to support professional information management by:
1. **Secure Documentation**: Enables professionals to create presentations without data leakage concerns
2. **Compliance Support**: Built-in classification and export controls help meet organizational security requirements
3. **Collaboration Tools**: Git integration supports team-based workflows while maintaining privacy controls
4. **Information Sovereignty**: Professionals maintain control over their presentation content and metadata
5. **Transparent Practices**: Open-source nature allows organizations to verify security practices and customize as needed