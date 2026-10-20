"""Validate Engineer's file-only credential boundary without a vault or Docker."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RENDERER = Path(sys.argv.pop(1)).resolve()
PARSER = Path(sys.argv.pop(1)).resolve()
SECRET = "fixture$#=${HOME}=literal"
POLICY = {
    "DISCORD_ALLOWED_USERS": "123,456",
    "DISCORD_ALLOW_ALL_USERS": "false",
    "DISCORD_REQUIRE_MENTION": "true",
    "DISCORD_ALLOW_BOTS": "none",
}


class EngineerEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.discord = self.root / "discord"
        self.provider = self.root / "provider"
        self.settings = self.root / "settings.json"
        self.target = self.root / "runtime" / ".env"
        self.discord.write_text(f"DISCORD_BOT_TOKEN={SECRET}\n")
        self.provider.write_text(f"HERMES_OMNIROUTE_API_KEY={SECRET}\n")
        self.settings.write_text(json.dumps({"policy": POLICY, "owner": [os.getuid(), os.getgid()]}))

    def run_renderer(self):
        return subprocess.run(
            [sys.executable, str(RENDERER), str(PARSER), str(self.discord),
             str(self.provider), str(self.settings), str(self.target)],
            capture_output=True, text=True,
            env=dict(os.environ, DISCORD_ALLOW_ALL_USERS="true", DISCORD_ALLOWED_USERS="999"),
        )

    def assert_failure(self):
        result = self.run_renderer()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")

    def test_valid_sources_publish_literals_policy_and_private_modes(self):
        result = self.run_renderer()
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = {"DISCORD_BOT_TOKEN": SECRET, "HERMES_OMNIROUTE_API_KEY": SECRET, **POLICY}
        actual = dict(line.split("=", 1) for line in self.target.read_text().splitlines())
        self.assertEqual(actual, expected)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o400)
        self.assertEqual(self.target.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.target.stat().st_uid, self.target.stat().st_gid), (os.getuid(), os.getgid()))
        self.assertEqual(result.stdout + result.stderr, "")

    def test_source_scope_failures_preserve_previous_file(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        original = self.target.read_bytes()
        inode = self.target.stat().st_ino
        for path, key in ((self.discord, "DISCORD_BOT_TOKEN"),
                          (self.provider, "HERMES_OMNIROUTE_API_KEY")):
            good = path.read_text()
            for source in ("", "# missing\n", f"{key}=\n",
                           f"{key}={SECRET}\n{key}=duplicate\n",
                           f"{key}={SECRET}\nbad-key=bad\n",
                           f'{key}="{SECRET}"\n', f"{key}={SECRET} \n",
                           f"{key}={SECRET} # comment\n", f"{key}=bad\x00\n",
                           f"{key}={SECRET}\nAPI_SERVER_KEY=admin\n",
                           f"{key}={SECRET}\nOP_SERVICE_ACCOUNT_TOKEN=admin\n",
                           f"{key}={SECRET}\nDISCORD_ALLOW_ALL_USERS=true\n",
                           f"{key}={SECRET}\nDISCORD_ALLOWED_USERS=999\n",
                           # The right key in the wrong source must still fail.
                           f"DISCORD_BOT_TOKEN={SECRET}\nHERMES_OMNIROUTE_API_KEY={SECRET}\n"):
                with self.subTest(path=path.name, source=source):
                    path.write_text(source)
                    self.assert_failure()
                    self.assertEqual(self.target.read_bytes(), original)
                    self.assertEqual(self.target.stat().st_ino, inode)
                    self.assertEqual(list(self.target.parent.iterdir()), [self.target])
            path.write_text(good)

    def test_missing_source_fails_without_output(self):
        for path in (self.discord, self.provider):
            with self.subTest(path=path.name):
                good = path.read_text()
                path.unlink()
                self.assert_failure()
                self.assertFalse(self.target.exists())
                path.write_text(good)

    def test_successful_refresh_atomically_replaces_existing_file(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        with self.target.open() as old:
            self.discord.write_text("DISCORD_BOT_TOKEN=new-fixture\n")
            self.assertEqual(self.run_renderer().returncode, 0)
            self.assertIn(SECRET, old.read())
            self.assertIn("DISCORD_BOT_TOKEN=new-fixture\n", self.target.read_text())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o400)
        self.assertEqual(list(self.target.parent.iterdir()), [self.target])


if __name__ == "__main__":
    unittest.main()
