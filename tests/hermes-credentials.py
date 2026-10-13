"""Exercise startup refresh against a fake remote vault, with real file publication."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RENDERER = Path(sys.argv.pop(1)).resolve()
FAKE_TOKEN = "fake-service-account-token"
FAKE_SECRET = "literal$#=${HOME}=credential"


class CredentialsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / "runtime"
        self.token = self.root / "bootstrap"
        self.token.write_text(FAKE_TOKEN + "\n")
        self.vault = self.root / "vault.json"
        self.op = self.root / "op"
        self.op.write_text(f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
if os.environ.get("OP_SERVICE_ACCOUNT_TOKEN") != "fake-service-account-token":
    sys.exit(2)
if len(sys.argv) != 3 or sys.argv[1] != "read":
    sys.exit(2)
value = json.loads(pathlib.Path(__file__).with_name("vault.json").read_text())[sys.argv[2]]
if isinstance(value, dict):
    print(value["stderr"], file=sys.stderr)
    sys.exit(3)
sys.stdout.write(value)
''')
        self.op.chmod(0o700)
        key = self.root / "fixture-key"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
        self.key = key.read_text()
        self.values = {
            "op://fixture/dashboard": f"API_SERVER_KEY={FAKE_SECRET}\n",
            "op://fixture/discord": "DISCORD_BOT_TOKEN=fake-discord-key\nDISCORD_ALLOW_ALL_USERS=true\n",
            "op://fixture/key": self.key,
        }
        self.manifest = {
            "environment": [
                {"label": "dashboard", "reference": "op://fixture/dashboard", "requiredKeys": ["API_SERVER_KEY"]},
                {"label": "discord", "reference": "op://fixture/discord", "requiredKeys": ["DISCORD_BOT_TOKEN"]},
            ],
            "sshKey": "op://fixture/key",
            "policy": {"DISCORD_ALLOW_ALL_USERS": "false"},
        }
        self.references = self.root / "references.json"

    def run_renderer(self):
        self.vault.write_text(json.dumps(self.values))
        self.references.write_text(json.dumps(self.manifest))
        return subprocess.run(
            [sys.executable, str(RENDERER), str(self.op), str(self.token), str(self.references), str(self.target)],
            capture_output=True, text=True,
        )

    def assert_private_failure(self, result):
        self.assertNotEqual(result.returncode, 0)
        for value in (FAKE_TOKEN, FAKE_SECRET, self.key, "fake-discord-key"):
            self.assertNotIn(value, result.stdout + result.stderr)

    def test_complete_refresh_preserves_literals_key_and_policy(self):
        result = self.run_renderer()
        self.assertEqual(result.returncode, 0, "complete credentials must publish successfully")
        current = self.target / "current"
        self.assertEqual((current / ".env").read_text(),
                         "API_SERVER_KEY=literal$#=${HOME}=credential\nDISCORD_BOT_TOKEN=fake-discord-key\nDISCORD_ALLOW_ALL_USERS=false\n")
        self.assertEqual((current / "host-key").read_text(), self.key)
        self.assertEqual((current / ".env").stat().st_mode & 0o777, 0o400)
        self.assertEqual(current.stat().st_mode & 0o777, 0o700)
        self.assertNotIn(FAKE_TOKEN, (current / ".env").read_text())
        self.assertEqual(result.stdout + result.stderr, "")

    def test_second_fetch_failure_retains_previous_complete_generation(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        previous = os.readlink(self.target / "current")
        self.values["op://fixture/dashboard"] = "API_SERVER_KEY=changed-first-value\n"
        self.values["op://fixture/discord"] = {"stderr": FAKE_TOKEN + FAKE_SECRET}
        self.assert_private_failure(self.run_renderer())
        self.assertEqual(os.readlink(self.target / "current"), previous)
        self.assertIn(FAKE_SECRET, (self.target / "current" / ".env").read_text())

    def test_missing_required_value_does_not_publish(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        previous = os.readlink(self.target / "current")
        self.values["op://fixture/dashboard"] = "API_SERVER_KEY=\n"
        self.assert_private_failure(self.run_renderer())
        self.assertEqual(os.readlink(self.target / "current"), previous)

    def test_first_boot_failure_leaves_no_current_generation(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        self.target = self.root / "first-boot"
        self.values["op://fixture/discord"] = {"stderr": FAKE_SECRET}
        self.assert_private_failure(self.run_renderer())
        self.assertFalse((self.target / "current").exists())

    def test_invalid_dotenv_values_fail_before_publication(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        previous = os.readlink(self.target / "current")
        for source in ("API_SERVER_KEY=a\nAPI_SERVER_KEY=b\n", "bad-key=value\n",
                       "API_SERVER_KEY=value\x00\n", 'API_SERVER_KEY="quoted"\n',
                       "API_SERVER_KEY=value # parsed as a comment\n"):
            with self.subTest(source=source):
                self.values["op://fixture/dashboard"] = source
                self.assert_private_failure(self.run_renderer())
                self.assertEqual(os.readlink(self.target / "current"), previous)

    def test_bootstrap_token_cannot_enter_application_environment(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        previous = os.readlink(self.target / "current")
        self.values["op://fixture/dashboard"] += f"OP_SERVICE_ACCOUNT_TOKEN={FAKE_TOKEN}\n"
        self.assert_private_failure(self.run_renderer())
        self.assertEqual(os.readlink(self.target / "current"), previous)

    def test_invalid_private_key_preserves_previous_generation(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        previous = os.readlink(self.target / "current")
        self.values["op://fixture/key"] = "not a private key\n" + FAKE_SECRET
        self.assert_private_failure(self.run_renderer())
        self.assertEqual(os.readlink(self.target / "current"), previous)

    def test_restart_reads_changed_vault_value(self):
        self.assertEqual(self.run_renderer().returncode, 0)
        self.values["op://fixture/dashboard"] = "API_SERVER_KEY=fresh-key\n"
        self.assertEqual(self.run_renderer().returncode, 0)
        self.assertIn("API_SERVER_KEY=fresh-key\n", (self.target / "current" / ".env").read_text())
        self.assertNotIn(FAKE_SECRET, (self.target / "current" / ".env").read_text())


if __name__ == "__main__":
    unittest.main()
