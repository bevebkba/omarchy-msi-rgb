"""Exercise the CLI boundary without writing to USB hardware."""
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("controller", ROOT / "controller.py")


class ControllerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (ROOT / "controller.py").exists():
            raise AssertionError("controller.py is not implemented")
        cls.c = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.c)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.fake = self.folder / "msi-rgb"
        self.lock = self.folder / "device.lock"
        self.fake.write_text("#!/usr/bin/python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
        self.fake.chmod(0o755)

    def run_cli(self, action, **kwargs):
        return self.c.execute(action, executable=str(self.fake), lock_path=self.lock, **kwargs)

    @unittest.skipUnless(Path('/usr/bin/msi-rgb').is_file(), 'Requires separately installed msi-rgb backend')
    def test_catalog_covers_installed_binary(self):
        help_text = subprocess.check_output(["/usr/bin/msi-rgb", "--help"], text=True)
        groups = re.findall(r"\(([a-z_|]+)\)", help_text)
        data = self.c.catalog()
        self.assertEqual(data["keyboard"], groups[0].split("|"))
        self.assertEqual(data["aurora"], groups[1].split("|"))
        self.assertEqual(data["info"], ["help", "usage", "version"])

    def test_every_preset_maps_to_its_own_zone(self):
        for zone, flag in (("keyboard", "--keyboard"), ("aurora", "--aurora")):
            for preset in self.c.catalog()[zone]:
                with self.subTest(zone=zone, preset=preset):
                    self.assertEqual(self.c.command_args("apply", **{zone: preset}), [flag, preset])
        self.assertEqual(self.c.command_args("apply", keyboard="aqua", aurora="flux"),
                         ["--keyboard", "aqua", "--aurora", "flux"])

    def test_controls_map_to_all_remaining_commands(self):
        for action, args in (("off", ["--keyboard", "disable", "--aurora", "disable"]),
                             ("defaults", ["--keyboard", "default", "--aurora", "default"]),
                             ("demo", ["--demo"]), ("help", ["--help"]),
                             ("usage", ["--usage"]), ("version", ["--version"])):
            self.assertEqual(self.c.command_args(action), args)

    def test_rejects_invalid_or_empty_actions_before_execution(self):
        for action, options in (("apply", {}), ("apply", {"keyboard": "flux"}),
                                ("apply", {"aurora": "$(touch /tmp/no)"}),
                                ("nonsense", {}), ("demo", {"keyboard": "aqua"})):
            with self.subTest(action=action, options=options):
                result = self.run_cli(action, **options)
                self.assertFalse(result["ok"])
                self.assertNotIn("command", result)

    def test_success_requires_clean_hardware_output(self):
        result = self.run_cli("apply", keyboard="aqua")
        self.assertFalse(result["ok"], "Unexpected stdout must not hide a HID failure with exit 0")
        self.assertIn("--keyboard", result["output"])
        self.fake.write_text("#!/bin/sh\nexit 0\n")
        result = self.run_cli("apply", keyboard="aqua")
        self.assertTrue(result["ok"])

    def test_info_captures_output_and_exit_failures(self):
        self.assertEqual(json.loads(self.run_cli("version")["output"]), ["--version"])
        self.fake.write_text("#!/bin/sh\necho 'permission denied' >&2\nexit 1\n")
        result = self.run_cli("defaults")
        self.assertFalse(result["ok"])
        self.assertIn("permission denied", result["output"])

    def test_missing_executable_and_timeout_are_visible(self):
        self.fake.unlink()
        self.assertFalse(self.run_cli("help")["ok"])
        self.fake.write_text("#!/usr/bin/python3\nimport time\ntime.sleep(10)\n")
        self.fake.chmod(0o755)
        result = self.run_cli("demo", timeout=0.05)
        self.assertFalse(result["ok"])
        self.assertTrue(result["timedOut"])
        self.fake.write_text("#!/bin/sh\nexit 0\n")
        self.assertTrue(self.run_cli("off")["ok"], "Timeout must release device lock")

    def test_concurrent_hardware_command_does_not_run(self):
        import fcntl
        with self.lock.open("w") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_cli("defaults")
            self.assertFalse(result["ok"])
            self.assertIn("busy", result["output"])
            self.assertTrue(self.run_cli("help")["ok"], "Read-only help need not wait for USB")

    def test_demo_cancellation_terminates_child_and_releases_lock(self):
        child_pid = self.folder / "child.pid"
        self.fake.write_text("#!/usr/bin/python3\nimport os,time\n"
                             f"open({str(child_pid)!r}, 'w').write(str(os.getpid()))\n"
                             "time.sleep(30)\n")
        # The harness imports the real controller but injects only the USB executable and lock path.
        runner = subprocess.Popen([sys.executable, "-c",
            "import sys,json; sys.path.insert(0,sys.argv[1]); import controller; "
            "print(json.dumps(controller.execute('demo', executable=sys.argv[2], lock_path=sys.argv[3])))",
            str(ROOT), str(self.fake), str(self.lock)], stdout=subprocess.PIPE, text=True)
        self.addCleanup(lambda: runner.poll() is None and runner.kill())
        deadline = time.monotonic() + 3
        while not child_pid.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(child_pid.exists(), "Fake USB process did not start")
        pid = int(child_pid.read_text())
        runner.terminate()
        output, _ = runner.communicate(timeout=3)
        result = json.loads(output)
        self.assertTrue(result["cancelled"])
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        self.fake.write_text("#!/bin/sh\nexit 0\n")
        self.assertTrue(self.run_cli("off")["ok"])

    def test_demo_stop_escalates_when_child_ignores_termination(self):
        ready = self.folder / "ready"
        self.fake.write_text("#!/usr/bin/python3\nimport signal,time\n"
                             "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                             f"open({str(ready)!r}, 'w').write('ready')\n"
                             "time.sleep(30)\n")
        runner = self.start_supervisor()
        self.wait_for_file(ready)
        started = time.monotonic()
        runner.terminate()
        output, _ = runner.communicate(timeout=2)
        result = json.loads(output)
        self.assertLess(time.monotonic() - started, 1.7)
        self.assertTrue(result["cancelled"])
        self.assertFalse(result["timedOut"])

    def test_killed_supervisor_cannot_leave_a_live_demo(self):
        child_pid = self.folder / "child.pid"
        self.fake.write_text("#!/usr/bin/python3\nimport os,time\n"
                             f"open({str(child_pid)!r}, 'w').write(str(os.getpid()))\n"
                             "time.sleep(30)\n")
        runner = self.start_supervisor()
        self.wait_for_file(child_pid)
        pid = int(child_pid.read_text())
        self.addCleanup(lambda: self.kill_if_alive(pid))
        runner.kill()
        runner.wait(timeout=1)
        deadline = time.monotonic() + 1
        while self.live_process(pid) and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(self.live_process(pid), "Shell unloading must not orphan a writing demo")

    def start_supervisor(self):
        process = subprocess.Popen([sys.executable, "-c",
            "import sys,json; sys.path.insert(0,sys.argv[1]); import controller; "
            "print(json.dumps(controller.execute('demo', executable=sys.argv[2], lock_path=sys.argv[3])))",
            str(ROOT), str(self.fake), str(self.lock)], stdout=subprocess.PIPE, text=True)
        self.addCleanup(lambda: self.kill_and_reap(process))
        return process

    def wait_for_file(self, path):
        deadline = time.monotonic() + 3
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(path.exists())

    @staticmethod
    def live_process(pid):
        try:
            return Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1][0] != "Z"
        except FileNotFoundError:
            return False

    @staticmethod
    def kill_if_alive(pid):
        with contextlib.suppress(ProcessLookupError):
            os.kill(pid, 9)

    @staticmethod
    def kill_and_reap(process):
        if process.poll() is None:
            process.kill()
        with contextlib.suppress(subprocess.TimeoutExpired):
            process.communicate(timeout=1)


if __name__ == "__main__":
    unittest.main()
