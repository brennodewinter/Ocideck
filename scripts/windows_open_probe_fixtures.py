#!/usr/bin/env python3
"""Create private, reproducible inputs for the installed Windows UI probe."""

import hashlib
import json
from pathlib import Path
import sys
import uuid
import zipfile


def create_fixtures(destination: Path) -> dict:
    destination.mkdir(parents=True, exist_ok=False)
    token = uuid.uuid4().hex
    scenarios = []
    for kind in ("markdown", "package"):
        marker = f"OpenProbe-{kind}-{token}"
        project = destination / f"{kind} presentatie é met spaties"
        project.mkdir()
        # >20 slides exercises the production warm-up batches, not only parse.
        body = "\r\n---\r\n\r\n".join(
            f"# {marker if i == 0 else f'Dia {i + 1}'}\r\n\r\nControle {i + 1}."
            for i in range(48)
        )
        content = f"---\r\nmarp: true\r\ntitle: {marker}\r\n---\r\n\r\n{body}\r\n"
        md = project / "presentatie.md"
        md.write_bytes(content.encode("utf-8-sig"))
        (project / "ocideck-style.json").write_text(
            json.dumps({"name": "Releaseproef", "logoSize": 96}), encoding="utf-8"
        )
        if kind == "package":
            source = destination / "pakket met spaties é.ocideck"
            with zipfile.ZipFile(source, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for member in sorted(project.iterdir()):
                    archive.write(member, member.name)
        else:
            source = md
        scenarios.append({"kind": kind, "path": str(source.resolve()), "marker": marker})
    hashes = {
        str(path.relative_to(destination)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(destination.rglob("*")) if path.is_file()
    }
    manifest = {"scenarios": scenarios, "sourceHashes": hashes}
    (destination / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return manifest


if __name__ == "__main__":
    create_fixtures(Path(sys.argv[1]))
