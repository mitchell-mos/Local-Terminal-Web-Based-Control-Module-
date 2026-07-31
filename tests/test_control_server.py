from __future__ import annotations

import importlib.util
import http.client
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import threading
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("control_server", ROOT / "control_server.py")
assert SPEC and SPEC.loader
control_server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(control_server)


def private_mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


class ControlServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        control_server.PROJECTS_FILE = self.root / "control-projects.json"
        control_server.LOG_DIR = self.root / "control-logs"
        control_server.RUNTIME_DIR = self.root / ".control-runtime"
        control_server.SESSION_TOKEN_FILE = control_server.RUNTIME_DIR / "session-token"
        control_server.SESSION_TOKEN = ""
        control_server.PROJECT_DATA_BACKUP = None
        control_server.PROCESSES.clear()
        control_server.PROCESS_ERRORS.clear()
        control_server.PROCESS_STOP_REASONS.clear()
        control_server.HEALTHY_PROJECTS.clear()

    def tearDown(self) -> None:
        control_server.stop_all_processes()
        self.temporary.cleanup()

    def test_first_run_is_empty_and_private(self) -> None:
        self.assertEqual(control_server.read_projects(), [])
        self.assertEqual(json.loads(control_server.PROJECTS_FILE.read_text()), [])
        self.assertEqual(private_mode(control_server.PROJECTS_FILE), 0o600)

    def test_corrupt_data_is_preserved_and_reported(self) -> None:
        control_server.PROJECTS_FILE.write_text("not-json", encoding="utf-8")
        with self.assertRaises(control_server.ProjectDataError):
            control_server.read_projects()
        backups = list(self.root.glob("control-projects.corrupt-*.json"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(encoding="utf-8"), "not-json")
        self.assertEqual(private_mode(backups[0]), 0o600)

    def test_session_token_is_private_and_stable(self) -> None:
        first = control_server.ensure_session_token()
        second = control_server.ensure_session_token()
        self.assertEqual(first, second)
        self.assertGreaterEqual(len(first), 32)
        self.assertEqual(private_mode(control_server.RUNTIME_DIR), 0o700)
        self.assertEqual(private_mode(control_server.SESSION_TOKEN_FILE), 0o600)

    def test_session_token_rotates_for_a_new_runner(self) -> None:
        first = control_server.rotate_session_token()
        second = control_server.rotate_session_token()
        self.assertNotEqual(first, second)
        self.assertEqual(control_server.SESSION_TOKEN_FILE.read_text().strip(), second)
        self.assertEqual(private_mode(control_server.SESSION_TOKEN_FILE), 0o600)

    def test_project_environment_does_not_inherit_secrets(self) -> None:
        previous = os.environ.get("CONTROL_MODULE_TEST_SECRET")
        os.environ["CONTROL_MODULE_TEST_SECRET"] = "do-not-copy"
        try:
            environment = control_server.project_environment()
        finally:
            if previous is None:
                os.environ.pop("CONTROL_MODULE_TEST_SECRET", None)
            else:
                os.environ["CONTROL_MODULE_TEST_SECRET"] = previous
        self.assertNotIn("CONTROL_MODULE_TEST_SECRET", environment)
        self.assertIn("PATH", environment)
        self.assertIn("HOME", environment)

    def test_runner_rejects_unauthorized_browser_requests(self) -> None:
        try:
            server = control_server.BoundedThreadingHTTPServer(
                ("127.0.0.1", 0),
                control_server.ControlHandler,
            )
        except PermissionError:
            self.skipTest("the current sandbox does not permit local HTTP tests")

        port = server.server_address[1]
        previous_hosts = control_server.ALLOWED_HOSTS
        previous_origins = control_server.ALLOWED_ORIGINS
        control_server.ALLOWED_HOSTS = {f"127.0.0.1:{port}"}
        control_server.ALLOWED_ORIGINS = {"http://127.0.0.1:1025"}
        token = control_server.rotate_session_token()
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def status(path: str, headers: dict[str, str]) -> int:
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
            try:
                connection.request("GET", path, headers=headers)
                response = connection.getresponse()
                response.read()
                return response.status
            finally:
                connection.close()

        try:
            self.assertEqual(status("/health", {}), 403)
            self.assertEqual(status("/health", {"X-Control-Token": token}), 200)
            self.assertEqual(
                status("/api/projects", {"X-Control-Token": token}),
                403,
            )
            self.assertEqual(
                status(
                    "/api/projects",
                    {
                        "Origin": "https://example.com",
                        "X-Control-Token": token,
                    },
                ),
                403,
            )
            self.assertEqual(
                status(
                    "/api/projects",
                    {
                        "Origin": "http://127.0.0.1:1025",
                        "X-Control-Token": token,
                    },
                ),
                200,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
            control_server.ALLOWED_HOSTS = previous_hosts
            control_server.ALLOWED_ORIGINS = previous_origins

    @unittest.skipUnless(sys.platform == "darwin", "listener ownership uses macOS lsof")
    def test_only_owned_process_group_is_stopped(self) -> None:
        with socket.socket() as probe:
            try:
                probe.bind(("127.0.0.1", 0))
            except PermissionError:
                self.skipTest("the current sandbox does not permit local listener tests")
            port = probe.getsockname()[1]
        command = [sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"]
        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        control_server.PROCESSES["owned-test"] = process
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and not control_server.port_is_open("127.0.0.1", port):
            time.sleep(0.05)
        self.assertTrue(control_server.port_is_owned_by_process_group(port, process.pid))
        self.assertTrue(control_server.stop_process("owned-test"))
        self.assertTrue(control_server.wait_for_port_to_close("127.0.0.1", port, timeout=3))


if __name__ == "__main__":
    unittest.main()
