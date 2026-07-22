# OciDeck — Frequently Asked Questions

> **Status:** current-state answers; where one conflicts with the code, the code wins · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

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
- **Security Focused**: There is no application backend for editing; your deck is
  processed on your device. The network requests that do happen — including the
  few whose address you did not choose — are listed in
  [PRIVACY.md](PRIVACY.md#what-leaves-your-device--and-only-when-you-ask).
- **Privacy First**: Built-in privacy scanning (OciWacht) to detect sensitive information
- **Marp Compatible**: Reads and writes standard Marp Markdown, so a deck stays
  usable in other Marp tools
- **Cross-platform**: Builds for macOS, Windows and Linux desktop, and for the
  browser
- **No Telemetry**: Zero tracking or analytics of any kind

### Is OciDeck free to use?
Yes. OciDeck is released under the EUPL-1.2 open-source licence, which costs
nothing and lets you use, study, change and redistribute it.

There is, however, **nothing to download yet**. No version has been tagged, no
signed build is published, and there is no download page or installer. The only
way to run OciDeck today is to build it from source — see
[BUILD.md](BUILD.md) and the *Getting started* section of the
[README](../README.md), which needs the pinned Flutter toolchain. *Corrected
2026-07-21: this answer used to say OciDeck is "completely free to download and
use", which described a distribution that does not exist.*

## Security and Privacy

### What security measures does OciDeck implement?
OciDeck implements several security layers:
- No application backend for editing. The one optional server-side component is
  the web build's CORS fetch-proxy (`server/fetch-proxy/`), which relays raw
  bytes only — see [ARCHITECTURE.md](ARCHITECTURE.md#runtime--network-model)
  *(corrected 2026-07-22: this said "client-side only architecture with no
  backend", which the section two headings above already contradicted)*
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
- **Images**: PNG, JPEG, GIF, BMP, WebP (validated by content/magic bytes, not by file extension)
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
OciDeck supports the following chart types:
- Bar charts (vertical, stacked, horizontal, horizontal stacked)
- Line and area charts  
- Pie and donut charts
- Radar/spider charts
- Scatter plots
- Waterfall charts
- Heatmaps (which double as risk matrices)
- Combo charts (bars plus the last series drawn as a line on a second axis)

### How does the AI assistant work?
The optional AI assistance requires explicit user consent:
1. Enabled in its own **Settings → AI Assistant** tab (off by default)
2. Requires configuration of a local model or an outbound endpoint; using a
   cloud/outbound endpoint additionally requires the general outbound-privacy
   consent under **Settings → License and Privacy**
3. Used for generating text suggestions and alt-text for images  
4. All data processing stays within the user's control

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

In the browser there are no recovery snapshots — the app has nowhere to write
them — so step 2 does not apply there and unsaved work is gone. The app says so
at your first edit, and the browser asks before you close a tab that still holds
unsaved work. Save early if you work in a browser tab.

## Configuration and Settings

### How does Git integration work?
OciDeck supports Git repository storage:
- Configure it as a connection under *Settings → Storage*, alongside folders,
  WebDAV and S3 *(corrected 21-07-2026; there is no separate "Git Repository"
  tab — storage is one list)*
- Save decks to remote repositories via REST API or native Git
- Supports both public and private repositories  
- Provides version history access
- Note what a commit carries: the markdown, the pooled images and the linked
  chart data. Video, audio, the drawings on your slides and the user notes do
  **not** travel this way; OciDeck counts them and asks before it commits. Save
  to a folder or an `.ocideck` package if you need those to come along.

### What are the WebDAV settings for?

WebDAV lets you store presentations directly on your own server. Nextcloud is
the most common one, but any WebDAV server works:
1. Pick the server type — *Nextcloud or ownCloud* (the DAV path is derived) or
   *Other WebDAV server* (the path in the server URL is the WebDAV root)
2. Configure server URL, credentials, and optional subfolder in Settings
3. Open decks via "Open from…" and pick the server
4. Save back with the ordinary save button; "Save to…" puts it elsewhere
5. Supports both flat format (.md + assets) or package formats

### How does S3 storage work?

S3 lets you keep decks in a bucket — AWS S3, or any S3-compatible service such
as MinIO or a European provider:

1. Add an S3 connection in Settings → Storage
2. Fill in the endpoint, bucket, region, access key ID and secret access key.
   The endpoint is a free text field rather than a list of AWS regions, because
   self-hosted and non-AWS endpoints are the interesting case
3. Pick the addressing style: bucket in the host name (AWS) or in the path (most
   self-hosted endpoints)
4. Open and save through "Open from…" and "Save to…"

Your secret access key goes to the OS keychain; the endpoint, bucket and access
key ID are ordinary settings. A MinIO box on your own LAN needs the *trusted
internal server* tick, since private addresses are blocked by default.

One difference is worth knowing: S3 is object storage, not a filesystem, so it
has no real folders. A prefix behaves like one, and listing uses a delimiter so
prefixes show up as if they were folders.

## Future Features and Roadmap

### What's planned for future development?
What is planned is decided in the issue tracker, in the open. There is no
separate roadmap document, because one that nobody maintains is worse than
none — this section was itself the proof: it listed encrypted package export
as planned for months after it had shipped, and "additional chart
visualizations" while thirteen chart types were already in the app.

What OciDeck does *not* do yet is written down, in one place:
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

*Corrected 2026-07-22: this answer listed three stale roadmap items. The
earlier correction of 2026-07-18, about encrypted package export having
shipped, is folded into this note.*

### Are there mobile plans?
Nothing is planned. The supported targets are macOS, Windows, Linux and the
browser: those are the ones with `make build-*` recipes, the ones the CI
workflow names, and the ones anything is tested on. The repository does contain
`android/` and `ios/` folders, but only because `flutter create` writes them —
no build target points at them, no test runs there, and the desktop file model
(sibling asset folders next to the opened `.md`) does not fit a mobile sandbox.

*(Corrected 2026-07-22: this answer said "the team continues to evaluate mobile
platform support based on community feedback and requirements". Neither the team
nor the feedback process it describes exists — twelve lines further down, this
same file says there is no discussion forum, mailing list or chat channel.)*

## Contributing and Community

### How can I contribute to OciDeck development?  
Community contributions are welcome through:
- Bug reports and feature requests via the project's issue tracker (Forgejo)
- Code contributions following project guidelines
- Documentation improvements 
- Testing new features in development builds

There is no discussion forum, mailing list or chat channel — the issue tracker
is the only channel for questions and reports.

For **security news** that is not the whole answer, and saying only the above was
misleading: you should not have to watch a tracker to learn that a vulnerability
was fixed. The forge serves a releases feed you can subscribe to, and
`SECURITY.md` explains what it carries today and what it does not. Corrected
2026-07-22.

### Where can I find more information?
The documentation in this repository is all of it: the `docs/` directory and the
source code itself. There is no separate documentation site, no community forum,
and no release notes — nothing has been tagged as a release yet. Corrected
2026-07-19.

### How does OciDeck fit into professional information management?
OciDeck is designed to support professional information management by:
1. **Secure Documentation**: Enables professionals to create presentations without data leakage concerns
2. **Compliance Support**: Built-in classification and export controls help meet organizational security requirements
3. **Collaboration Tools**: Git integration supports team-based workflows while maintaining privacy controls
4. **Information Sovereignty**: Professionals maintain control over their presentation content and metadata
5. **Transparent Practices**: Open-source nature allows organizations to verify security practices and customize as needed