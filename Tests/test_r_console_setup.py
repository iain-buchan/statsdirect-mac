"""First-use setup checks without downloading packages or changing user libraries."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Content/R/console-setup.R"
RSCRIPT = os.environ.get("R_SCRIPT") or shutil.which("Rscript")
PRIVATE_LIBRARY = Path(os.environ.get(
    "STATSDIRECT_CONSOLE_R_LIBRARY",
    str(Path.home() / "Library/Application Support/StatsDirect Viewer/R Library")))


@unittest.skipUnless(RSCRIPT, "Rscript is not installed")
class RConsoleSetupTests(unittest.TestCase):
    def run_setup(self, *args, env=None):
        return subprocess.run(
            [RSCRIPT, "--vanilla", str(SCRIPT), *map(str, args)],
            capture_output=True, text=True, timeout=30, env=env)

    def test_functional_private_library_probe_does_not_modify_packages(self):
        if not PRIVATE_LIBRARY.is_dir():
            self.skipTest("The private chart library has not been prepared")
        before = sorted(p.relative_to(PRIVATE_LIBRARY).as_posix()
                        for p in PRIVATE_LIBRARY.rglob("*"))
        result = self.run_setup("--probe", PRIVATE_LIBRARY)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("STATSDIRECT_CONSOLE_READY svglite=", result.stdout)
        self.assertEqual(before, sorted(p.relative_to(PRIVATE_LIBRARY).as_posix()
                                       for p in PRIVATE_LIBRARY.rglob("*")))

    def test_probe_never_installs_into_empty_or_default_user_library(self):
        with tempfile.TemporaryDirectory(prefix="statsdirect-r-setup-") as parent:
            private = Path(parent) / "private"; private.mkdir()
            user = Path(parent) / "user"; user.mkdir()
            sentinel = user / "keep.txt"; sentinel.write_text("user library is unchanged")
            environment = {**os.environ, "R_LIBS_USER": str(user)}
            result = self.run_setup("--probe", private, env=environment)
            # A system R library may already supply compatible chart support.
            self.assertIn(result.returncode, (0, 23), result.stdout + result.stderr)
            self.assertEqual(list(private.iterdir()), [])
            self.assertEqual(list(user.iterdir()), [sentinel])
            self.assertEqual(sentinel.read_text(), "user library is unchanged")

    def test_invalid_mode_fails_without_starting_installation(self):
        with tempfile.TemporaryDirectory(prefix="statsdirect-r-setup-") as folder:
            result = self.run_setup("--unknown", folder)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Invalid R chart setup request", result.stderr)
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_install_requires_a_private_staging_directory(self):
        with tempfile.TemporaryDirectory(prefix="statsdirect-r-setup-") as folder:
            result = self.run_setup("--install", folder)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue("Missing private setup directory" in result.stderr
                            or "requires the Mac version of R" in result.stderr,
                            result.stderr)
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_intel_r_metadata_requests_native_install_before_package_work(self):
        with tempfile.TemporaryDirectory(prefix="statsdirect-r-setup-") as folder:
            expression = """
              args <- commandArgs(trailingOnly=TRUE)
              commandArgs <- function(trailingOnly=FALSE) {
                if (trailingOnly) args[-1L] else base::commandArgs(FALSE)
              }
              R.version <- base::R.version
              R.version$arch <- "x86_64"
              source(args[[1L]])
            """
            result = subprocess.run(
                [RSCRIPT, "--vanilla", "-e", expression, str(SCRIPT), "--probe", folder],
                capture_output=True, text=True, timeout=30)
            if os.uname().sysname != "Darwin":
                self.skipTest("Mac architecture guard")
            self.assertEqual(result.returncode, 24, result.stdout + result.stderr)
            self.assertIn("native Apple Silicon R", result.stderr)
            self.assertEqual(list(Path(folder).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
