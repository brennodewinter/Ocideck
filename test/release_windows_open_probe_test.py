"""Check probe inputs and that release promotion requires the installed UI probe."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "windows_open_probe_fixtures", ROOT / "scripts/windows_open_probe_fixtures.py"
)
FIXTURES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURES)


class WindowsOpenProbeTests(unittest.TestCase):
    def test_worker_script_encoding_is_safe_for_windows_powershell_51(self):
        # The native worker runs in Windows PowerShell, which reads BOM-less
        # scripts as the Windows code page. Unicode belongs in fixtures/JSON.
        self.assertTrue((ROOT / "scripts/windows_open_probe.ps1").read_bytes().isascii())

    def test_real_marp_inputs_cover_bom_crlf_48_slides_and_portable_style(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = FIXTURES.create_fixtures(Path(temporary) / "fixtures")
            self.assertEqual([s["kind"] for s in manifest["scenarios"]], ["markdown", "package"])
            self.assertEqual(len({s["marker"] for s in manifest["scenarios"]}), 2)
            for scenario in manifest["scenarios"]:
                path = Path(scenario["path"])
                self.assertIn("é", str(path))
                self.assertIn(" ", str(path))
                if scenario["kind"] == "package":
                    with zipfile.ZipFile(path) as archive:
                        self.assertEqual(archive.testzip(), None)
                        self.assertEqual(set(archive.namelist()), {"presentatie.md", "ocideck-style.json"})
                        raw = archive.read("presentatie.md")
                        style = json.loads(archive.read("ocideck-style.json"))
                else:
                    raw = path.read_bytes()
                    style = json.loads(path.with_name("ocideck-style.json").read_text())
                self.assertTrue(raw.startswith(b"\xef\xbb\xbf---\r\nmarp: true\r\n"))
                text = raw.decode("utf-8-sig")
                self.assertEqual(sum(line.startswith("# ") for line in text.splitlines()), 48)
                self.assertIn(f"title: {scenario['marker']}\r\n", text)
                self.assertEqual(style["logoSize"], 96)
                self.assertNotEqual(path.stem, scenario["marker"])

    def test_refuses_stale_evidence_and_generates_fresh_markers(self):
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first"
            a = FIXTURES.create_fixtures(first)
            with self.assertRaises(FileExistsError):
                FIXTURES.create_fixtures(first)
            b = FIXTURES.create_fixtures(Path(temporary) / "second")
            self.assertNotEqual(a["scenarios"][0]["marker"], b["scenarios"][0]["marker"])

    def test_release_probes_installed_payload_before_cohort_and_preserves_failure_evidence(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        smoke_name = '      - name: "Smoke-test: installeren, starten, verwijderen"'
        smoke = workflow.split(smoke_name, 1)[1].split('\n      - name:', 1)[0]
        probe = smoke.index("& ./scripts/windows_open_probe.ps1")
        self.assertIn('-Executable "$doel\\ocideck.exe"', smoke[probe:])
        self.assertLess(probe, smoke.index("# 4. Stil verwijderen"))
        self.assertNotIn("continue-on-error", smoke)
        evidence_name = '      - name: Bewaar bewijs van de Windows-openproef'
        evidence = workflow.split(evidence_name, 1)[1].split('\n      - name:', 1)[0]
        self.assertLess(workflow.index(smoke_name), workflow.index('      - name: Cohortattest voor de forge'))
        self.assertIn('if: always()', evidence)
        self.assertIn('path: build/windows-open-probe/', evidence)


if __name__ == "__main__":
    unittest.main()
