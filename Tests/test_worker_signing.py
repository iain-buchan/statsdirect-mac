"""Verify worker-only signing policy on isolated copies; no certificates or UI."""
from pathlib import Path
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
worker_argument = __name__ == "__main__" and len(sys.argv) > 1 and not sys.argv[1].startswith("-")
WORKER = Path(sys.argv[1] if worker_argument else
              ROOT / "StatsDirect.app/Contents/MacOS/RConsoleWorker").resolve()
if worker_argument:
    del sys.argv[1]


@unittest.skipUnless(sys.platform == "darwin", "Mac signing check")
class WorkerSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not WORKER.is_file():
            raise RuntimeError("Build the release RConsoleWorker before this check")
        cls.temporary = tempfile.TemporaryDirectory(prefix="worker-signing-", dir=ROOT / ".build")
        cls.folder = Path(cls.temporary.name)
        cls.app = cls.folder / "Signing Fixture.app"
        cls.main = cls.app / "Contents/MacOS/StatsDirect"
        cls.worker = cls.app / "Contents/MacOS/RConsoleWorker"
        cls.other = cls.app / "Contents/Helpers/Other"
        cls.main.parent.mkdir(parents=True); cls.other.parent.mkdir(parents=True)
        for target in (cls.main, cls.worker, cls.other):
            shutil.copy2(WORKER, target)
        info = dict(CFBundleIdentifier="com.statsdirect.worker-signing-test",
                    CFBundleExecutable="StatsDirect", CFBundleName="Signing Fixture",
                    CFBundlePackageType="APPL", CFBundleVersion="1.1.0",
                    CFBundleShortVersionString="1.1.0", LSMinimumSystemVersion="14.0",
                    StatsDirectInteractiveRConsole=True)
        (cls.app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_main_and_worker_source_policies_are_separate(self):
        main = plistlib.loads((ROOT / "StatsDirect.entitlements").read_bytes())
        worker = plistlib.loads((ROOT / "RConsoleWorker.entitlements").read_bytes())
        self.assertEqual(main, {"com.apple.security.cs.allow-jit": True})
        self.assertEqual(worker, {"com.apple.security.cs.allow-jit": True,
                                 "com.apple.security.cs.disable-library-validation": True})

    def test_developer_id_routing_without_keychain_access(self):
        # A recording signer exercises the real script's Developer ID branch.
        # It cannot contact SecurityAgent, sign anything or show a credential prompt.
        tools = self.folder / "tools"; tools.mkdir(exist_ok=True)
        record = self.folder / "signing.json"
        signer = tools / "codesign"
        signer.write_text("#!" + sys.executable + "\n" + """
import json, os, plistlib, sys
from pathlib import Path
p=Path(os.environ['STATSDIRECT_SIGNING_RECORD'])
d=json.loads(p.read_text()) if p.exists() else {}
a=sys.argv[1:]; target=a[-1]
if '--sign' in a:
    d[target]=plistlib.loads(Path(a[a.index('--entitlements')+1]).read_bytes())
    p.write_text(json.dumps(d))
elif '--display' in a:
    sys.stdout.buffer.write(plistlib.dumps(d[target]))
""")
        signer.chmod(0o700)
        assessor = tools / "spctl"; assessor.write_text("#!/bin/sh\nexit 0\n"); assessor.chmod(0o700)
        env = {**os.environ, "PATH": str(tools) + os.pathsep + os.environ.get("PATH", os.defpath),
               "STATSDIRECT_SIGNING_RECORD": str(record)}
        result = subprocess.run(["/bin/zsh", str(ROOT / "Scripts/sign-app.sh"), str(self.app),
                                 "FIXTURE-IDENTITY-NO-KEYCHAIN"], env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout)
        signed = json.loads(record.read_text())
        strict = {"com.apple.security.cs.allow-jit": True}
        relaxed = {**strict, "com.apple.security.cs.disable-library-validation": True}
        self.assertEqual(signed[str(self.worker)], relaxed)
        for path in (self.main, self.other, self.app):
            self.assertEqual(signed[str(path)], strict)

    def test_hardened_adhoc_signature_and_real_r_worker(self):
        result = subprocess.run(["/bin/zsh", str(ROOT / "Scripts/sign-app.sh"), str(self.app), "-"],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout)
        metadata = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=4", str(self.worker)],
                                  capture_output=True, text=True, check=True)
        self.assertIn("runtime", metadata.stderr)
        entitlements = subprocess.run(["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml",
                                      str(self.worker)], capture_output=True, check=True)
        source = entitlements.stdout + entitlements.stderr
        start = source.index(b"<?xml")
        end = source.index(b"</plist>", start) + len(b"</plist>")
        self.assertEqual(plistlib.loads(source[start:end]), {
            "com.apple.security.cs.allow-jit": True,
            "com.apple.security.cs.disable-library-validation": True})
        # Real libR and real native SVG packages run under the hardened worker.
        checks = subprocess.run([sys.executable, str(ROOT / "Tests/test_interactive_r_worker.py"),
                                  str(self.worker)], text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=180)
        self.assertEqual(checks.returncode, 0, checks.stdout)
        self.assertGreaterEqual(checks.stdout.count("PASS:"), 39, checks.stdout)
        print(checks.stdout, end="")


if __name__ == "__main__":
    unittest.main()
