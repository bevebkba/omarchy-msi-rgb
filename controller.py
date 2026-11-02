#!/usr/bin/python3
"""Validated, serialized access to the installed MSI GE66 CLI."""
import argparse
from contextlib import nullcontext
import ctypes
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import time

KEYBOARD = ["aqua", "chakra", "default", "disable", "disco", "dragon_shield",
            "drain", "free_way", "plain", "rainbow_split"]
AURORA = ["aurora", "blue_flash", "casino", "chakra", "default", "disable",
          "disco", "dragon_shield", "flux", "macaw", "plain", "rainbow"]
INFO = ["help", "usage", "version"]


def child_lifetime(parent_pid, libc):
    # Quickshell may SIGKILL the supervisor while unloading a Process object.
    # Linux then kills this direct CLI child as well, before another writer starts.
    if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:  # PR_SET_PDEATHSIG
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    if os.getppid() != parent_pid:
        os.kill(os.getpid(), signal.SIGKILL)


def catalog():
    return {"ok": True, "keyboard": KEYBOARD, "aurora": AURORA, "info": INFO}


def command_args(action, keyboard=None, aurora=None):
    if action == "apply":
        if keyboard is None and aurora is None:
            raise ValueError("Select at least one preset.")
        args = []
        for zone, preset, allowed in (("keyboard", keyboard, KEYBOARD), ("aurora", aurora, AURORA)):
            if preset is not None:
                if preset not in allowed:
                    raise ValueError(f"Invalid {zone} preset: {preset}")
                args += ["--" + zone, preset]
        return args
    if keyboard is not None or aurora is not None:
        raise ValueError("This command does not accept preset parameters.")
    if action in ("off", "defaults"):
        preset = "disable" if action == "off" else "default"
        return ["--keyboard", preset, "--aurora", preset]
    if action in INFO + ["demo"]:
        return ["--" + action]
    raise ValueError("Invalid command.")


def execute(action, keyboard=None, aurora=None, *, executable="/usr/bin/msi-rgb", lock_path=None, timeout=None):
    try:
        args = command_args(action, keyboard, aurora)
    except ValueError as error:
        return {"ok": False, "output": str(error)}
    command = [executable] + args
    hardware = action not in INFO
    result = {"ok": False, "command": command, "output": "", "cancelled": False, "timedOut": False}
    child = None
    old_handlers = {}

    def request_stop(_signum, _frame):
        result["cancelled"] = True
        if child is not None and child.poll() is None:
            child.terminate()

    def stop_child():
        if child is None:
            return ""
        if child.poll() is None:
            child.terminate()
        try:
            return child.communicate(timeout=1)[0]
        except subprocess.TimeoutExpired:
            child.kill()
            return child.communicate()[0]

    try:
        if hardware:
            if lock_path is None:
                base = Path(os.environ.get("XDG_RUNTIME_DIR", Path.home() / ".local/state"))
                lock_path = base / "omarchy-ge66-rgb" / "device.lock"
            lock_path = Path(lock_path)
            lock_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (lock_path.open("a") if hardware else nullcontext()) as lock:
            if hardware:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    result["output"] = "RGB device is busy. Wait for the other command or demo to finish."
                    return result
            for sig in (signal.SIGTERM, signal.SIGINT):
                old_handlers[sig] = signal.signal(sig, request_stop)
            libc = ctypes.CDLL(None, use_errno=True)
            parent_pid = os.getpid()
            child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     text=True, errors="replace",
                                     pass_fds=(lock.fileno(),) if hardware else (),
                                     preexec_fn=lambda: child_lifetime(parent_pid, libc))
            if result["cancelled"]:
                child.terminate()
            deadline = time.monotonic() + (timeout if timeout is not None else (60 if action == "demo" else 10))
            while True:
                if result["cancelled"]:
                    output = stop_child()
                    break
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    result["timedOut"] = True
                    output = stop_child()
                    break
                try:
                    output, _ = child.communicate(timeout=min(0.1, remaining))
                    break
                except subprocess.TimeoutExpired:
                    continue
            result["code"] = child.returncode
            result["output"] = output.strip()
            if result["cancelled"]:
                result["output"] = "Demo/command stopped. The last lighting effect remains active."
            elif result["timedOut"]:
                result["output"] = "Command timed out and was stopped.\n" + result["output"]
            elif child.returncode == 0:
                # The CLI prints HID write failures on stdout but still exits zero.
                result["ok"] = not (hardware and action != "demo" and result["output"])
                if action == "demo" and result["output"]:
                    lines = result["output"].splitlines()
                    expected = {f"--keyboard {k} --aurora {a}" for k in KEYBOARD for a in AURORA}
                    result["ok"] = all(line in expected for line in lines)
            if not result["ok"] and not result["output"]:
                result["output"] = f"msi-rgb exit code: {child.returncode}"
    except OSError as error:
        result["output"] = str(error)
    finally:
        if child is not None and child.poll() is None:
            stop_child()
        for sig, previous in old_handlers.items():
            signal.signal(sig, previous)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["catalog", "apply", "defaults", "off", "demo"] + INFO)
    parser.add_argument("--keyboard")
    parser.add_argument("--aurora")
    args = parser.parse_args()
    result = catalog() if args.action == "catalog" else execute(args.action, args.keyboard, args.aurora)
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
