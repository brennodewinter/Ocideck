#!/usr/bin/env python3
"""Reject a desktop release that silently drops either supported Mac CPU.

Read Mach-O headers directly, so fixtures exercise the same gate on Linux and
Windows. Signing/notarization still establish executable validity separately.
The existing host-specific ffmpeg helper is outside this startup/Whisper gate;
it was already arm64-only in the published 0.7.14 bundle.
"""

import argparse
from pathlib import Path
import plistlib
import struct
import sys


REQUIRED = {"arm64", "x86_64"}
CPUS = {0x01000007: "x86_64", 0x0100000C: "arm64"}
THIN = {
    b"\xcf\xfa\xed\xfe": ("<", 32),
    b"\xfe\xed\xfa\xcf": (">", 32),
    b"\xce\xfa\xed\xfe": ("<", 28),
    b"\xfe\xed\xfa\xce": (">", 28),
}
FAT = {
    b"\xca\xfe\xba\xbe": (">", False),
    b"\xbe\xba\xfe\xca": ("<", False),
    b"\xca\xfe\xba\xbf": (">", True),
    b"\xbf\xba\xfe\xca": ("<", True),
}


class ArchitectureError(ValueError):
    pass


def thin_cpu(header, size):
    layout = THIN.get(header[:4])
    if layout is None or size < layout[1] or len(header) < layout[1]:
        raise ArchitectureError("missing or truncated Mach-O slice")
    return struct.unpack(layout[0] + "I", header[4:8])[0]


def architectures(path):
    """Return CPUs for Mach-O files, None for data; reject malformed headers."""
    size = path.stat().st_size
    with path.open("rb") as stream:
        header = stream.read(32)
        if header[:4] in THIN:
            cpus = {thin_cpu(header, size)}
        elif header[:4] in FAT:
            if len(header) < 8:
                raise ArchitectureError("truncated universal header")
            endian, wide = FAT[header[:4]]
            count = struct.unpack(endian + "I", header[4:8])[0]
            if not 1 <= count <= 16:
                raise ArchitectureError("invalid universal slice count")
            stride = 32 if wide else 20
            end = 8 + count * stride
            stream.seek(8)
            table = stream.read(count * stride)
            if len(table) != count * stride:
                raise ArchitectureError("truncated universal slice table")
            cpus, ranges = set(), []
            for index in range(count):
                entry = table[index * stride:(index + 1) * stride]
                fmt = endian + ("IIQQII" if wide else "IIIII")
                cpu, _, offset, length, align, *_ = struct.unpack(fmt, entry)
                if (offset < end or length < 28 or offset + length > size
                        or align > 63 or offset % (1 << align)):
                    raise ArchitectureError("invalid universal slice bounds")
                if any(offset < b and a < offset + length for a, b in ranges):
                    raise ArchitectureError("overlapping universal slices")
                stream.seek(offset)
                if thin_cpu(stream.read(min(32, length)), length) != cpu:
                    raise ArchitectureError("slice CPU disagrees with table")
                if cpu in cpus:
                    raise ArchitectureError("duplicate universal CPU")
                cpus.add(cpu)
                ranges.append((offset, offset + length))
        else:
            return None
    return {CPUS.get(cpu, hex(cpu)) for cpu in cpus}


def check_bundle(app):
    app = app.resolve(strict=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or Path(executable).name != executable:
        raise ArchitectureError("invalid bundle executable name")
    required = {
        app / "Contents/MacOS" / executable,
        app / "Contents/Frameworks/App.framework/App",
        app / "Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS",
        app / "Contents/Helpers/whisper-cli",
    }
    files = set(required)
    for directory in [app / "Contents/MacOS", app / "Contents/Frameworks"]:
        files.update(p for p in directory.rglob("*") if p.is_file())
    checked, seen = [], set()
    for path in sorted(files):
        real = path.resolve(strict=True)
        if not real.is_relative_to(app):
            raise ArchitectureError(f"code points outside bundle: {path}")
        if real in seen:
            continue
        seen.add(real)
        cpus = architectures(real)
        if cpus is None and path not in required:
            continue
        if cpus is None or not REQUIRED.issubset(cpus):
            actual = ", ".join(sorted(cpus or [])) or "not Mach-O"
            raise ArchitectureError(f"{path.relative_to(app)}: needs arm64 and "
                                    f"x86_64, found {actual}")
        checked.append(str(path.relative_to(app)))
    return checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        checked = check_bundle(args.app)
    except (ArchitectureError, OSError, plistlib.InvalidFileException) as error:
        print(f"macOS architecture gate FAILED: {error}", file=sys.stderr)
        return 1
    print(f"macOS Universal gate: {len(checked)} native binaries contain "
          "both arm64 and x86_64")
    return 0


if __name__ == "__main__":
    sys.exit(main())
