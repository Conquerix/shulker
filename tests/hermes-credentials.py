"""Exercise shared OpNix file scope and atomic generation publication, offline."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RENDERER = Path(sys.argv.pop(1)).resolve()
SECRET = "fixture$#=${HOME}=literal"
POLICY = {"DISCORD_ALLOW_ALL_USERS": "false", "DISCORD_ALLOWED_USERS": "123",
          "DISCORD_REQUIRE_MENTION": "true", "DISCORD_ALLOW_BOTS": "none"}


class CredentialsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / "runtime"
        self.manifest = self.root / "manifest.json"
        self.sources = {"discord": "DISCORD_BOT_TOKEN", "provider": "HERMES_OMNIROUTE_API_KEY"}
        for label, key in self.sources.items():
            (self.root / label).write_text(f"{key}={SECRET}\n")
        self.settings = {
            "environment": [{"label": label, "path": str(self.root / label), "requiredKeys": [key]}
                            for label, key in self.sources.items()],
            "policy": POLICY, "owner": [os.getuid(), os.getgid()], "sshKey": None}

    def run_renderer(self):
        self.manifest.write_text(json.dumps(self.settings))
        return subprocess.run([sys.executable, str(RENDERER), str(self.manifest), str(self.target)],
                              capture_output=True, text=True,
                              env=dict(os.environ, DISCORD_ALLOW_ALL_USERS="true"))

    def failure(self):
        result = self.run_renderer()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")

    def test_literals_policy_private_modes_and_refresh(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        target = self.target / "current" / ".env"
        actual = dict(line.split("=", 1) for line in target.read_text().splitlines())
        self.assertEqual(actual, {key: SECRET for key in self.sources.values()} | POLICY)
        self.assertEqual(target.stat().st_mode & 0o777, 0o400)
        self.assertEqual(target.parent.stat().st_mode & 0o777, 0o700)
        previous = os.readlink(self.target / "current")
        (self.root / "discord").write_text("DISCORD_BOT_TOKEN=fresh\n")
        self.assertEqual(self.run_renderer().returncode, 0)
        self.assertNotEqual(previous, os.readlink(self.target / "current"))
        self.assertIn("DISCORD_BOT_TOKEN=fresh\n", target.read_text())

    def test_all_source_failures_preserve_generation(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        previous = os.readlink(self.target / "current")
        for label, key in self.sources.items():
            path = self.root / label
            good = path.read_text()
            for text in ("", "# absent\n", f"{key}=\n", f"{key}=a\n{key}=b\n",
                         f"{key}=bad\x00\n", f'{key}="quoted"\n', f"{key}=value \n",
                         f"{key}=value # comment\n", f"{key}=value\nEXTRA_KEY=bad\n",
                         f"{key}=value\nDISCORD_ALLOW_ALL_USERS=true\n",
                         f"{key}=value\nOP_SERVICE_ACCOUNT_TOKEN=bad\n", "bad-key=value\n"):
                with self.subTest(label=label, text=text):
                    path.write_text(text)
                    self.failure()
                    self.assertEqual(previous, os.readlink(self.target / "current"))
            path.unlink()
            self.failure()
            path.write_text(good)

    def test_first_failure_publishes_nothing(self):
        (self.root / "provider").unlink()
        self.failure()
        self.assertFalse((self.target / "current").exists())

    def test_ssh_key_validated_before_joint_publication(self):
        key = self.root / "host-key"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
        self.settings["sshKey"] = str(key)
        self.assertEqual(self.run_renderer().returncode, 0)
        previous = os.readlink(self.target / "current")
        self.assertEqual((self.target / "current" / "host-key").read_bytes(), key.read_bytes())
        key.write_text(SECRET)
        self.failure()
        self.assertEqual(previous, os.readlink(self.target / "current"))

    def test_dashboard_exact_source_and_cross_source_duplicate(self):
        dashboard = self.root / "dashboard"
        keys = ["HERMES_DASHBOARD_BASIC_AUTH_USERNAME", "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET", "API_SERVER_KEY"]
        dashboard.write_text("".join(f"{key}={SECRET}\n" for key in keys))
        self.settings["environment"].append({"path": str(dashboard), "requiredKeys": keys})
        self.assertEqual(self.run_renderer().returncode, 0)
        dashboard.write_text(f"API_SERVER_KEY={SECRET}\n")
        self.failure()
        self.settings["environment"].append(self.settings["environment"][0])
        self.failure()


if __name__ == "__main__":
    unittest.main()
