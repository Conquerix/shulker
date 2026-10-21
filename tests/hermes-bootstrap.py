"""Bootstrap guards and failure atomicity (native CLI contract simulated, not integration)."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1)).resolve()
spec = importlib.util.spec_from_file_location("bootstrap", SOURCE)
assert spec is not None and spec.loader is not None
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "data"
        self.home.mkdir()
        self.settings = {"files": {}, "settings": {"model.default": "fixture-model"}, "plugins": ["discord-platform"]}

    def test_existing_native_state_never_runs_cli(self):
        target = self.home / "config.yaml"
        target.write_text("learned state\n")
        bootstrap.bootstrap_native(self.settings, self.home)
        self.assertEqual(target.read_text(), "learned state\n")
        self.assertEqual(list(self.home.iterdir()), [target])

    def test_files_create_once_and_preserve_symlinks(self):
        source = self.root / "initial.txt"
        source.write_text("initial")
        self.settings["files"] = {"data/identity.md": str(source), "workspace/notes.md": str(source)}
        bootstrap.bootstrap_files(self.settings, self.root)
        target = self.home / "identity.md"
        target.write_text("learned")
        bootstrap.bootstrap_files(self.settings, self.root)
        self.assertEqual(target.read_text(), "learned")
        target.unlink()
        target.symlink_to(self.root / "absent")
        bootstrap.bootstrap_files(self.settings, self.root)
        self.assertTrue(target.is_symlink())
        self.assertFalse((self.root / "absent").exists())

    def test_bad_file_paths_rejected(self):
        for target in ("../elsewhere", "data/../../elsewhere", "/absolute", "data/config.yaml", "data/./config.yaml", "data//config.yaml"):
            with self.subTest(target=target), self.assertRaises(ValueError):
                bootstrap.bootstrap_files({"files": {target: "unused"}}, self.root)

    def test_native_commands_publish_only_after_all_succeed(self):
        binary = self.root / "hermes"
        binary.write_text(f"#!{sys.executable}\n" + '''
import os, pathlib, sys
p = pathlib.Path(os.environ["HERMES_HOME"]) / "config.yaml"
with p.open("a") as f:
    f.write(" ".join(sys.argv[1:]) + "\\n")
if os.environ.get("FIXTURE_FAIL"):
    sys.exit(1)
''')
        binary.chmod(0o700)
        old = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(old)))
        os.environ["PATH"] = str(self.root) + os.pathsep + os.environ["PATH"]
        os.environ["FIXTURE_FAIL"] = "1"
        with self.assertRaises(subprocess.CalledProcessError):
            bootstrap.bootstrap_native(self.settings, self.home)
        self.assertFalse((self.home / "config.yaml").exists())
        del os.environ["FIXTURE_FAIL"]
        bootstrap.bootstrap_native(self.settings, self.home)
        self.assertEqual((self.home / "config.yaml").read_text(),
                         "config set model.default fixture-model\nplugins enable discord-platform\n")
        self.assertEqual(list(self.home.iterdir()), [self.home / "config.yaml"])


if __name__ == "__main__":
    unittest.main()
