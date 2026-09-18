#!/usr/bin/env python3
"""Exercise the real backup shell against isolated Docker, systemd and ZFS state."""

import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PREPARE, BASH = sys.argv[1:3]
del sys.argv[1:3]
SERVICES = ("webserver", "database", "broker", "tika", "gotenberg")
NAMES = ("paperless_webserver", "paperless_postgres", "paperless_broker", "paperless_tika", "paperless_gotenberg")

STUB = r'''
import json, os, re, signal, sys, time
from pathlib import Path
state_file = Path(os.environ["TEST_STATE"])
state = json.loads(state_file.read_text())
args = sys.argv[1:]
command = Path(sys.argv[0]).name
scenario = os.environ.get("TEST_SCENARIO", "success")
code = 0
output = ""
interrupt = False
state["events"].append([command, *args])

def container(key):
    for item in state["containers"]:
        if key in (item["id"], item["name"]):
            return item
    raise ValueError("missing container")

try:
    if command == "systemctl":
        if args[0] == "is-active":
            code = 0 if state["active"] else 3
        elif args[0] == "show":
            output = state["invocation"]
        elif args[0] == "stop":
            state["active"] = False
            for item in state["containers"]:
                item["running"] = False
        elif args[0] == "start":
            state["active"] = True
            for number, item in enumerate(state["containers"], 101):
                item["id"] = f"{number:064x}"
                item["running"] = True
        else:
            raise ValueError("unexpected systemctl command")
    elif command == "docker":
        if args[0] == "ps":
            output = "\n".join(item["id"] for item in state["containers"])
        elif args[0] == "inspect":
            if scenario == "inspect-hangs":
                time.sleep(30)
            item = container(args[-1])
            template = args[args.index("--format") + 1]
            values = {
                ".Id": item["id"],
                ".State.Running": str(item["running"]).lower(),
                ".State.ExitCode": str(item.get("exit_code", 0)),
                ".State.OOMKilled": "false",
                'index .Config.Labels "com.docker.compose.project"': item.get("project", "paperless"),
                'index .Config.Labels "com.docker.compose.service"': item["service"],
                "if .State.Health": "healthy" if item["running"] else "starting",
            }
            if ".State.Health" in template:
                output = "healthy" if item["running"] else "starting"
                if scenario == "unhealthy-resume" and state["resumed"]:
                    output = "unhealthy"
                if scenario == "partial-dependency-unhealthy" and state.get("dump_quiesced") and item["service"] == "database":
                    output = "unhealthy"
            else:
                output = re.sub(r"{{(.*?)}}", lambda match: values[match[1]], template)
        elif args[0] == "stop":
            item = container(args[-1])
            if scenario == "stop-fails-before" and item["service"] == "webserver":
                code = 1
            else:
                item["running"] = False
                if scenario == "interrupted-stop" and item["service"] == "webserver":
                    interrupt = True
                if scenario == "stop-fails-after" and item["service"] == "webserver":
                    code = 1
                if scenario == "killed-writer" and item["service"] == "webserver":
                    item["exit_code"] = 137
        elif args[0] == "start":
            item = container(args[-1])
            state["resumed"] = True
            if scenario == "resume-fails-once" and not state.get("resume_failed"):
                state["resume_failed"] = True
                code = 1
            else:
                if item["service"] == "webserver":
                    assert all(other["running"] for other in state["containers"] if other["service"] != "webserver")
                item["running"] = True
                item["exit_code"] = 0
        else:
            raise ValueError("unexpected Docker mutation")
    elif command == "zfs":
        if args[0] == "list":
            code = 0 if state["snapshot"] else 1
        elif args[0] == "snapshot":
            state["snapshot_quiesced"] = not any(item["running"] for item in state["containers"])
            if scenario == "snapshot-fails":
                code = 1
            else:
                state["snapshot"] = True
                if scenario == "snapshot-fails-after":
                    code = 1
        elif args[0] == "destroy":
            state["snapshot"] = False
        else:
            raise ValueError("unexpected ZFS command")
    elif command == "paperless-logical-under-test":
        if scenario == "dump-hangs":
            time.sleep(5)
        state["dump_quiesced"] = not container("paperless_webserver")["running"]
        assert container("paperless_postgres")["running"]
        if scenario in ("dump-fails", "partial-dependency-unhealthy", "partial-dependency-stopped"):
            code = 1
            if scenario == "partial-dependency-stopped":
                container("paperless_postgres")["running"] = False
        elif scenario == "intentional-shutdown":
            state["active"] = False
            for item in state["containers"]:
                item["running"] = False
        elif scenario == "new-invocation":
            state["invocation"] = "b" * 32
        elif scenario == "replacement":
            container("paperless_webserver")["id"] = "f" * 64
    elif command == "paperless-health-under-test":
        assert state["active"] and all(item["running"] for item in state["containers"])
        if scenario == "post-health-fails" and state["resumed"]:
            code = 1
    elif command in ("flock", "sleep"):
        pass
    else:
        raise ValueError("unexpected command")
except (ValueError, KeyError, AssertionError):
    code = 98
    print("invalid simulated operation", file=sys.stderr)
state_file.write_text(json.dumps(state))
if interrupt:
    os.kill(int(os.environ["TEST_SHELL_PID"]), signal.SIGTERM)
if output:
    print(output)
sys.exit(code)
'''


class BackupTransaction(unittest.TestCase):
    def run_prepare(self, scenario="success"):
        with tempfile.TemporaryDirectory(prefix="paperless-backup-") as directory:
            root = Path(directory)
            containers = [
                {"id": f"{number:064x}", "name": name, "service": service, "running": True}
                for number, (name, service) in enumerate(zip(NAMES, SERVICES), 1)
            ]
            if scenario == "foreign-label":
                containers[0]["project"] = "foreign"
            if scenario == "extra-container":
                containers.append({"id": "e" * 64, "name": "orphan", "service": "extra", "running": True})
            state = {
                "active": True, "invocation": "a" * 32, "snapshot": False,
                "resumed": False, "containers": containers, "events": [],
            }
            state_file = root / "state.json"
            state_file.write_text(json.dumps(state))
            bin_dir = root / "bin"
            bin_dir.mkdir()
            for command in ("docker", "systemctl", "zfs", "flock", "sleep", "paperless-logical-under-test", "paperless-health-under-test"):
                executable = bin_dir / command
                executable.write_text(f"#!{sys.executable}\n" + STUB)
                executable.chmod(0o755)
            if scenario == "dump-hangs":
                # Shorten only the real dump deadline; other calls keep their
                # production durations and the real coreutils timeout behavior.
                deadline = bin_dir / "timeout"
                deadline.write_text(
                    f"#!{sys.executable}\nimport os, sys\n"
                    "args = sys.argv[1:]\n"
                    "if args[-1] == 'paperless-logical-under-test':\n"
                    "    assert args[:2] == ['--kill-after=30', '900']\n"
                    "    args[:2] = ['--kill-after=1', '0.1']\n"
                    f"os.execv({shutil.which('timeout')!r}, ['timeout', *args])\n"
                )
                deadline.chmod(0o755)
            environment = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                               TEST_STATE=str(state_file), TEST_SCENARIO=scenario,
                               PAPERLESS_MAINTENANCE_LOCK=str(root / "lock"))
            if scenario == "post-snapshot-fails":
                environment["PAPERLESS_BACKUP_TEST_FAIL_AFTER_SNAPSHOT"] = "1"
            result = subprocess.run([BASH, "-c", 'export TEST_SHELL_PID=$$; exec "$@"',
                                     "test", BASH, "-euo", "pipefail", PREPARE], env=environment,
                                    capture_output=True, text=True, timeout=45)
            final = json.loads(state_file.read_text())
            self.assertNotIn("invalid simulated operation", result.stderr, result.stderr)
            return result, final

    def assert_recovered(self, state):
        self.assertTrue(all(item["running"] for item in state["containers"]))
        self.assertEqual([item["id"] for item in state["containers"]], [f"{number:064x}" for number in range(1, 6)])
        self.assertFalse(state["snapshot"])

    def test_success_reuses_existing_containers(self):
        result, state = self.run_prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([item["id"] for item in state["containers"]], [f"{number:064x}" for number in range(1, 6)],
                         "backup must retain the containers and their remapped writable layers")
        self.assertTrue(all(item["running"] for item in state["containers"]))
        self.assertTrue(state["snapshot"])
        self.assertFalse(any(event[:2] in (["systemctl", "stop"], ["systemctl", "start"]) for event in state["events"]))

    def test_dump_and_snapshot_have_quiesced_writers(self):
        result, state = self.run_prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(state["dump_quiesced"], "logical dump must follow application writer shutdown")
        self.assertTrue(state["snapshot_quiesced"], "snapshot requires every container to be stopped")

    def test_failures_recover_same_containers_and_clean_snapshot(self):
        for scenario in ("stop-fails-before", "stop-fails-after", "dump-fails", "snapshot-fails", "snapshot-fails-after", "post-snapshot-fails", "resume-fails-once", "post-health-fails", "killed-writer", "interrupted-stop"):
            with self.subTest(scenario=scenario):
                result, state = self.run_prepare(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assert_recovered(state)

    def test_dump_timeout_recovers_writer(self):
        result, state = self.run_prepare("dump-hangs")
        self.assertEqual(result.returncode, 124)
        self.assert_recovered(state)

    def test_partial_stop_recovery_checks_untouched_dependencies(self):
        for scenario in ("partial-dependency-unhealthy", "partial-dependency-stopped"):
            with self.subTest(scenario=scenario):
                result, state = self.run_prepare(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(state["containers"][0]["running"])
                self.assertFalse(any(event[:2] == ["docker", "start"] for event in state["events"]))
                self.assertFalse(state["snapshot"])

    def test_slow_docker_read_is_bounded(self):
        result, state = self.run_prepare("inspect-hangs")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(event[:2] == ["docker", "stop"] for event in state["events"]))

    def test_unhealthy_resume_does_not_start_dependent_writer(self):
        result, state = self.run_prepare("unhealthy-resume")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(state["snapshot"])
        self.assertFalse(state["containers"][0]["running"])
        self.assertFalse(any(event[:2] == ["docker", "start"] and event[-1] == "0" * 63 + "1"
                             for event in state["events"]))

    def test_foreign_or_extra_containers_are_not_stopped(self):
        for scenario in ("foreign-label", "extra-container"):
            with self.subTest(scenario=scenario):
                result, state = self.run_prepare(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(event[:2] == ["docker", "stop"] for event in state["events"]))
                self.assertFalse(state["snapshot"])

    def test_shutdown_or_replacement_never_resurrects_containers(self):
        for scenario in ("intentional-shutdown", "new-invocation", "replacement"):
            with self.subTest(scenario=scenario):
                result, state = self.run_prepare(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(event[:2] == ["docker", "start"] for event in state["events"]))
                self.assertFalse(state["snapshot"])


if __name__ == "__main__":
    unittest.main()
