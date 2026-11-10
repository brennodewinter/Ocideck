# OciDeck Linux distribution terms

OciDeck's own source code remains licensed under EUPL-1.2. See LICENSE.md.
Each third-party component retains its copyright and licence notices.

## GPL media combination

The Linux application can load the distribution's GPL-licensed libmpv and
FFmpeg builds. For this combination we exercise the compatibility provision in
EUPL-1.2 article 5 and its Appendix: the combined work is distributed under
GPL-3.0-or-later, with that licence prevailing where the terms conflict.
This does not replace the primary EUPL-1.2 licence of OciDeck's own source,
or relicense independent third-party components, documents or exported decks.
Do not represent this Linux combination as exclusively EUPL-licensed.

Git is a separate executable, distributed as an aggregate in Flatpak under its
own GPL terms. System libraries and the separately supplied GNOME runtime keep
their respective licences. The runtime's exact OSTree commit is recorded.

## Source, rebuilding and replacement

The installed bundle's share/doc/ocideck directory contains the EUPL and GNU
licence texts, notices, a source archive and a build/provenance manifest.
The archive contains the exact project snapshot, resolved package sources,
their licences and build scripts. Extract it and follow REBUILD.md.
The same versioned source archive is provided next to the release downloads.

Flatpak additionally includes share/doc/ocideck-flatpak/SOURCES.json and
sources/: exact distro source packages, including distro patches and build
recipes, for every distro package whose files we copy. Full package copyrights
and GNU texts are in licenses/. FILES.sha256 covers the delivered files.
GNU source delivery is by accompanying source, not a promise to provide it
later. Redistributors must pass these sources and notices on with binaries.

Libraries installed separately by apt/dnf or supplied by the GNOME runtime
are not copied into native OciDeck packages. Their distributors provide their
sources. The manifest distinguishes these prerequisites from copied files.

You may modify, replace and rebuild the libraries and the application, and
reverse engineer the application for debugging modifications to LGPL libraries.
There is no OciDeck signature check, activation, DRM or installation key that
prevents running those modifications. The native launcher uses ordinary shared
libraries; Flatpak users can rebuild the bundle or use a development override.
See REBUILD.md for commands. No additional EULA restricts these rights.

## No warranty

The applicable licences disclaim warranty. This notice does not grant patent
rights beyond those granted by the respective licences. It is not a statement
that a particular codec is free of patent claims in every jurisdiction.

References:
- https://interoperable-europe.ec.europa.eu/collection/eupl/faqs
- https://www.gnu.org/licenses/gpl-3.0.html (sections 1, 5 and 6)
- https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html (section 6)
- https://ffmpeg.org/legal.html

Independent release channels embed their build-specific source archive in each
artifact. The full release candidate also publishes the standalone Ubuntu
source archive; independent channels keep disjoint asset ownership.
