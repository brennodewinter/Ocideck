import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "macos_architectures",
    Path(__file__).resolve().parents[1] / "tool/check_macos_architectures.py",
)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)
ARM = 0x0100000C
INTEL = 0x01000007


def thin(cpu):
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 0, 0, 0, 0)


def universal(cpus=(ARM, INTEL), wide=False, endian=">"):
    stride = 32 if wide else 20
    offset = 8 + len(cpus) * stride
    magic = 0xCAFEBABF if wide else 0xCAFEBABE
    header = struct.pack(endian + "II", magic, len(cpus))
    entries, slices = b"", b""
    for cpu in cpus:
        data = thin(cpu)
        fmt = endian + ("IIQQII" if wide else "IIIII")
        values = (cpu, 0, offset, len(data), 0, 0) if wide else (
            cpu, 0, offset, len(data), 0)
        entries += struct.pack(fmt, *values)
        slices += data
        offset += len(data)
    return header + entries + slices


class MacOSArchitectureTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "OciDeck.app"
        info = self.app / "Contents/Info.plist"
        info.parent.mkdir(parents=True)
        info.write_bytes(plistlib.dumps({"CFBundleExecutable": "OciDeck"}))
        self.required = [
            "Contents/MacOS/OciDeck", "Contents/Frameworks/App.framework/App",
            "Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS",
            "Contents/Helpers/whisper-cli",
        ]
        for relative in self.required:
            self.write(relative, universal())

    def write(self, relative, content):
        path = self.app / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def test_universal_startup_and_whisper_pass_with_host_ffmpeg_unchanged(self):
        self.write("Contents/Helpers/ffmpeg", thin(ARM))
        self.assertEqual(len(gate.check_bundle(self.app)), 4)

    def test_arm_only_regression_fails_for_each_required_component(self):
        for relative in self.required:
            with self.subTest(component=relative):
                self.write(relative, thin(ARM))
                with self.assertRaisesRegex(gate.ArchitectureError, "x86_64"):
                    gate.check_bundle(self.app)
                self.write(relative, universal())

    def test_thin_native_plugin_also_fails(self):
        self.write("Contents/Frameworks/plugin.framework/plugin", thin(INTEL))
        with self.assertRaisesRegex(gate.ArchitectureError, "plugin.framework"):
            gate.check_bundle(self.app)

    def test_missing_required_component_fails(self):
        (self.app / self.required[1]).unlink()
        with self.assertRaises(OSError):
            gate.check_bundle(self.app)

    def test_framework_alias_is_checked_without_counting_twice(self):
        alias = self.app / "Contents/Frameworks/alias.dylib"
        alias.symlink_to("App.framework/App")
        self.assertEqual(len(gate.check_bundle(self.app)), 4)

    def test_outside_bundle_code_is_refused(self):
        outside = Path(self.temp.name) / "outside"
        outside.write_bytes(universal())
        (self.app / self.required[1]).unlink()
        (self.app / self.required[1]).symlink_to(outside)
        with self.assertRaisesRegex(gate.ArchitectureError, "outside"):
            gate.check_bundle(self.app)

    def test_both_fat_formats_and_byte_orders_are_read(self):
        for wide in [False, True]:
            for endian in ["<", ">"]:
                with self.subTest(wide=wide, endian=endian):
                    path = self.write("fixture", universal(wide=wide, endian=endian))
                    self.assertEqual(gate.architectures(path), gate.REQUIRED)

    def test_forged_table_cannot_hide_wrong_cpu_or_out_of_bounds_slice(self):
        for broken in [universal((ARM, ARM)), universal()[:-1],
                       universal()[:8], b"\xca\xfe\xba\xbe\0\0\0\xff"]:
            with self.subTest(header=broken[:8]):
                with self.assertRaises(gate.ArchitectureError):
                    gate.architectures(self.write("fixture", broken))
        broken = bytearray(universal())
        struct.pack_into(">I", broken, 8, INTEL)
        with self.assertRaisesRegex(gate.ArchitectureError, "disagrees"):
            gate.architectures(self.write("fixture", broken))


if __name__ == "__main__":
    unittest.main()
