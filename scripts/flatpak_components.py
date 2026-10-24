#!/usr/bin/env python3
"""Describe the distro binaries copied into the direct Flatpak bundle."""

import json
import sys
from pathlib import Path
from urllib.parse import quote


def main() -> None:
    packages_path, hashes_path, version, output_path = sys.argv[1:]
    packages = []
    for line in Path(packages_path).read_text().splitlines():
        name, package_version, arch = line.split("\t")
        packages.append({
            "type": "library",
            "name": name,
            "version": package_version,
            "purl": f"pkg:deb/ubuntu/{quote(name, safe='')}@{quote(package_version, safe='')}?arch={arch}&distro=ubuntu-24.04",
        })
    files = []
    for line in Path(hashes_path).read_text().splitlines():
        digest, path = line.split("  ", 1)
        if len(digest) != 64 or not path.startswith(("bin/", "lib/", "libexec/", "share/git-core/")):
            raise ValueError(f"Invalid copied-file record: {line}")
        files.append({
            "type": "file",
            "name": f"/app/{path}",
            "hashes": [{"alg": "SHA-256", "content": digest}],
        })
    if len(packages) != 6 or not files:
        raise ValueError("Flatpak component inventory is incomplete")
    document = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "version": 1,
        "metadata": {
            "component": {"type": "application", "name": "OciDeck Flatpak", "version": version},
            "properties": [{"name": "flatpak:runtime", "value": "org.gnome.Platform/x86_64/50"}],
        },
        "components": packages + files,
    }
    Path(output_path).write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("usage: flatpak_components.py PACKAGES.tsv FILES.sha256 VERSION OUTPUT")
    main()
