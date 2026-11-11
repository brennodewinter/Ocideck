#!/usr/bin/env python3
"""Describe the distro binaries copied into the direct Flatpak bundle."""

import json
import re
import sys
from pathlib import Path
from urllib.parse import quote


def main() -> None:
    packages_path, hashes_path, version, output_path = sys.argv[1:]
    notices = Path(packages_path).parent
    sources = json.loads((notices / 'SOURCES.json').read_text())
    source_by_binary = {r['binary']: r for r in sources['binary_packages']}
    runtime_commit = (notices / 'RUNTIME-COMMIT').read_text().strip()
    if not re.fullmatch(r'[0-9a-f]{64}', runtime_commit):
        raise ValueError('Missing exact GNOME runtime commit')
    packages = []
    for line in Path(packages_path).read_text().splitlines():
        name, package_version, arch = line.split("\t")
        source = source_by_binary[name]
        if source['version'] != package_version or source['architecture'] != arch:
            raise ValueError(f'Source inventory mismatch: {name}')
        packages.append({
            "type": "library",
            "name": name,
            "version": package_version,
            "purl": f"pkg:deb/ubuntu/{quote(name, safe='')}@{quote(package_version, safe='')}?arch={arch}&distro=ubuntu-24.04",
            "properties": [
                {"name": "debian:source:name", "value": source['source']},
                {"name": "debian:source:version", "value": source['source_version']},
                {"name": "ocideck:copyright", "value": f"/app/share/doc/ocideck-flatpak/licenses/{name.split(':')[0]}.copyright"},
                {"name": "ocideck:source-manifest", "value": "/app/share/doc/ocideck-flatpak/SOURCES.json"},
            ],
        })
    files = []
    for line in Path(hashes_path).read_text().splitlines():
        digest, path = line.split("  ", 1)
        if not re.fullmatch(r"[0-9a-f]{64}", digest) or ".." in Path(path).parts or not path.startswith(("bin/", "lib/", "libexec/", "share/git-core/", "share/doc/ocideck-flatpak/")):
            raise ValueError(f"Invalid copied-file record: {line}")
        files.append({
            "type": "file",
            "name": f"/app/{path}",
            "hashes": [{"alg": "SHA-256", "content": digest}],
        })
    if len(packages) < 11 or not files:
        raise ValueError("Flatpak component inventory is incomplete")
    document = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "version": 1,
        "metadata": {
            "component": {"type": "application", "name": "OciDeck Flatpak", "version": version,
                          "licenses": [{"license": {"id": "GPL-3.0-or-later"}}]},
            "properties": [
                {"name": "flatpak:runtime", "value": "org.gnome.Platform/x86_64/50"},
                {"name": "flatpak:runtime:commit", "value": runtime_commit},
                {"name": "ocideck:own-source-license", "value": "EUPL-1.2"},
                {"name": "ocideck:app-source-manifest", "value": "/app/lib/ocideck/share/doc/ocideck/BUILD-SOURCES.json"},
                {"name": "ocideck:distribution-terms", "value": "/app/lib/ocideck/share/doc/ocideck/DISTRIBUTION-LICENSES.md"},
            ],
        },
        "components": packages + files,
    }
    Path(output_path).write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("usage: flatpak_components.py PACKAGES.tsv FILES.sha256 VERSION OUTPUT")
    main()
