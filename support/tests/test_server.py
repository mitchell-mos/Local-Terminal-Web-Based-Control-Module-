from __future__ import annotations

import importlib.util
import http.client
import json
import os
import plistlib
import socket
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import threading
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("control_server", ROOT / "server" / "control_server.py")
assert SPEC and SPEC.loader
control_server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(control_server)


def private_mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


class ControlServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        control_server.DATA_DIR = self.root / "data"
        control_server.PROJECTS_FILE = control_server.DATA_DIR / "projects.json"
        control_server.LOG_DIR = control_server.DATA_DIR / "logs" / "projects"
        control_server.RUNTIME_DIR = control_server.DATA_DIR / "runtime"
        control_server.BACKUP_DIR = control_server.DATA_DIR / "backups"
        control_server.SESSION_TOKEN_FILE = control_server.RUNTIME_DIR / "session-token"
        control_server.SESSION_TOKEN = ""
        control_server.PROJECT_DATA_BACKUP = None
        control_server.PROCESSES.clear()
        control_server.PROCESS_ERRORS.clear()
        control_server.PROCESS_STOP_REASONS.clear()
        control_server.HEALTHY_PROJECTS.clear()
        control_server.LAST_ACTIONS.clear()

    def tearDown(self) -> None:
        control_server.stop_all_processes()
        self.temporary.cleanup()

    def test_first_run_is_empty_and_private(self) -> None:
        self.assertEqual(control_server.read_projects(), [])
        self.assertEqual(json.loads(control_server.PROJECTS_FILE.read_text()), [])
        self.assertEqual(private_mode(control_server.PROJECTS_FILE), 0o600)

    def test_project_reordering_requires_every_saved_project_once(self) -> None:
        projects = [
            {"id": "first-project", "name": "First"},
            {"id": "second-project", "name": "Second"},
            {"id": "third-project", "name": "Third"},
        ]

        reordered = control_server.reorder_project_records(
            projects,
            ["third-project", "first-project", "second-project"],
        )
        self.assertEqual(
            [project["id"] for project in reordered],
            ["third-project", "first-project", "second-project"],
        )
        self.assertIs(reordered[1], projects[0])

        for invalid_order in (
            ["first-project", "second-project"],
            ["first-project", "first-project", "third-project"],
            ["first-project", "second-project", "unknown-project"],
        ):
            with self.subTest(invalid_order=invalid_order):
                with self.assertRaisesRegex(ValueError, "exactly once"):
                    control_server.reorder_project_records(projects, invalid_order)
        with self.assertRaisesRegex(ValueError, "must be a list"):
            control_server.reorder_project_records(
                projects,
                "first-project,second-project,third-project",
            )

    def test_corrupt_data_is_preserved_and_reported(self) -> None:
        control_server.ensure_private_directory(control_server.PROJECTS_FILE.parent)
        control_server.PROJECTS_FILE.write_text("not-json", encoding="utf-8")
        with self.assertRaises(control_server.ProjectDataError):
            control_server.read_projects()
        backups = list(control_server.BACKUP_DIR.glob("control-projects.corrupt-*.json"))
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

    def test_instances_receive_distinct_session_tokens(self) -> None:
        first = control_server.rotate_session_token()
        second_runtime = self.root / "second-instance" / "runtime"
        control_server.RUNTIME_DIR = second_runtime
        control_server.SESSION_TOKEN_FILE = second_runtime / "session-token"
        control_server.SESSION_TOKEN = ""
        second = control_server.rotate_session_token()
        self.assertNotEqual(first, second)
        self.assertEqual(control_server.SESSION_TOKEN_FILE.read_text().strip(), second)

    def test_runner_port_configuration_is_validated(self) -> None:
        previous = os.environ.get("CONTROL_MODULE_RUNNER_PORT")
        try:
            os.environ["CONTROL_MODULE_RUNNER_PORT"] = "10425"
            self.assertEqual(control_server.configured_runner_port(), 10425)
            for invalid in ("not-a-port", "1024", "65536"):
                os.environ["CONTROL_MODULE_RUNNER_PORT"] = invalid
                self.assertEqual(control_server.configured_runner_port(), 10001)
        finally:
            if previous is None:
                os.environ.pop("CONTROL_MODULE_RUNNER_PORT", None)
            else:
                os.environ["CONTROL_MODULE_RUNNER_PORT"] = previous

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

    def test_dashboard_port_configuration_is_validated(self) -> None:
        previous = os.environ.get("CONTROL_MODULE_WEB_PORT")
        try:
            os.environ["CONTROL_MODULE_WEB_PORT"] = "14325"
            self.assertEqual(control_server.configured_web_port(), 14325)
            for invalid in ("not-a-port", "1024", "65536"):
                os.environ["CONTROL_MODULE_WEB_PORT"] = invalid
                self.assertEqual(control_server.configured_web_port(), 1025)

            os.environ["CONTROL_MODULE_WEB_PORT"] = str(control_server.PORT)
            self.assertEqual(control_server.configured_web_port(), 1025)
        finally:
            if previous is None:
                os.environ.pop("CONTROL_MODULE_WEB_PORT", None)
            else:
                os.environ["CONTROL_MODULE_WEB_PORT"] = previous

    def test_browser_blocked_project_ports_are_rejected_everywhere(self) -> None:
        expected = {
            1719, 1720, 1723, 2049, 3659, 4045, 5060, 5061,
            6000, 6566, 6665, 6666, 6667, 6668, 6669, 6697,
        }
        self.assertEqual(control_server.BROWSER_BLOCKED_PROJECT_PORTS, expected)

        project = self.root / "blocked-port-project"
        project.mkdir()
        for blocked_port in expected:
            reason = control_server.project_port_restriction_reason(blocked_port)
            self.assertIn("blocked by browsers", reason)
            self.assertEqual(
                control_server.port_unavailable_reason("127.0.0.1", blocked_port),
                reason,
            )
            with self.assertRaisesRegex(ValueError, "blocked by browsers"):
                control_server.inspect_project({
                    "path": str(project),
                    "port": blocked_port,
                    "kind": "auto",
                })
            with self.assertRaisesRegex(ValueError, "blocked by browsers"):
                control_server.validate_project({
                    "id": "blocked-port-project",
                    "name": "Blocked port project",
                    "host": "127.0.0.1",
                    "port": blocked_port,
                    "command": f"python3 -m http.server {blocked_port}",
                })

    def test_available_port_suggestions_skip_browser_blocked_ports(self) -> None:
        with mock.patch.object(control_server, "port_is_open", return_value=False):
            self.assertEqual(
                control_server.find_available_port("127.0.0.1", 5999),
                6001,
            )
            self.assertEqual(
                control_server.find_available_port("127.0.0.1", 6664),
                6670,
            )

    def test_basic_static_project_generates_a_shell_safe_command(self) -> None:
        project = self.root / "site with spaces"
        project.mkdir()
        (project / "index.html").write_text("<h1>Local</h1>\n", encoding="utf-8")

        inspected = control_server.inspect_project({
            "path": str(project),
            "port": 4321,
            "kind": "auto",
        })

        self.assertEqual(inspected["detectedKind"], "static")
        self.assertEqual(inspected["selectedKind"], "static")
        self.assertEqual(inspected["suggestedName"], "site with spaces")
        self.assertEqual(
            inspected["command"],
            f"cd -- '{project.resolve()}' && python3 -m http.server 4321 --bind 127.0.0.1",
        )

    def test_basic_vite_project_detects_a_compatible_script(self) -> None:
        project = self.root / "vite-project"
        project.mkdir()
        (project / "package.json").write_text(json.dumps({
            "name": "example-vite-site",
            "scripts": {"preview": "vite preview", "dev": "vite"},
            "devDependencies": {"vite": "latest"},
        }), encoding="utf-8")

        inspected = control_server.inspect_project({
            "path": str(project),
            "port": 4322,
            "kind": "auto",
        })

        self.assertEqual(inspected["detectedKind"], "vite")
        self.assertEqual(inspected["selectedScript"], "dev")
        self.assertEqual(inspected["scripts"], ["dev", "preview"])
        self.assertEqual(
            inspected["command"],
            f"cd -- {project.resolve()} && npm run dev -- --host 127.0.0.1 --port 4322",
        )

    def test_basic_next_project_uses_next_hostname_flag(self) -> None:
        project = self.root / "next-project"
        project.mkdir()
        (project / "package.json").write_text(json.dumps({
            "name": "example-next-site",
            "scripts": {"dev": "next dev"},
            "dependencies": {"next": "latest"},
        }), encoding="utf-8")

        inspected = control_server.inspect_project({
            "path": str(project),
            "port": 4323,
            "kind": "auto",
        })

        self.assertEqual(inspected["detectedKind"], "next")
        self.assertEqual(
            inspected["command"],
            f"cd -- {project.resolve()} && npm run dev -- --hostname 127.0.0.1 --port 4323",
        )

    def test_custom_package_script_is_detected_and_can_fall_back_to_static(self) -> None:
        project = self.root / "custom-package"
        project.mkdir()
        (project / "package.json").write_text(json.dumps({
            "name": "custom-package",
            "scripts": {"serve": "custom-server"},
            "dependencies": {"next": "latest", "vite": "latest"},
        }), encoding="utf-8")

        automatic = control_server.inspect_project({
            "path": str(project),
            "port": 4324,
            "kind": "auto",
        })
        static = control_server.inspect_project({
            "path": str(project),
            "port": 4324,
            "kind": "static",
        })

        self.assertEqual(automatic["detectedKind"], "package")
        self.assertEqual(automatic["selectedScript"], "serve")
        self.assertEqual(automatic["packageManager"], "npm")
        self.assertEqual(
            automatic["command"],
            f"cd -- {project.resolve()} && PORT=4324 HOST=127.0.0.1 npm run serve",
        )
        self.assertIn("python3 -m http.server 4324", static["command"])

    def test_project_inspection_uses_the_detected_package_manager(self) -> None:
        project = self.root / "pnpm-project"
        project.mkdir()
        (project / "package.json").write_text(json.dumps({
            "name": "pnpm-project",
            "scripts": {"dev": "vite"},
        }), encoding="utf-8")
        (project / "pnpm-lock.yaml").write_text("lockfileVersion: '9.0'\n", encoding="utf-8")

        inspected = control_server.inspect_project({
            "path": str(project),
            "port": 4326,
            "kind": "auto",
        })

        self.assertEqual(inspected["packageManager"], "pnpm")
        self.assertEqual(
            inspected["command"],
            f"cd -- {project.resolve()} && corepack pnpm run dev -- --host 127.0.0.1 --port 4326",
        )

    def test_optional_process_commands_are_validated_and_saved(self) -> None:
        validated = control_server.validate_project({
            "id": "custom-process",
            "name": "Custom process",
            "host": "127.0.0.1",
            "port": 4327,
            "command": "PORT=4327 npm run start",
            "setupCommand": "npm install",
            "stopCommand": "npm run stop",
            "restartCommand": "PORT=4327 npm run restart",
        })

        self.assertEqual(validated["setupCommand"], "npm install")
        self.assertEqual(validated["stopCommand"], "npm run stop")
        self.assertEqual(validated["restartCommand"], "PORT=4327 npm run restart")
        with self.assertRaisesRegex(ValueError, "setup command"):
            control_server.validate_project({
                **validated,
                "setupCommand": "x" * (control_server.MAX_OPTIONAL_COMMAND_LENGTH + 1),
            })
        with self.assertRaisesRegex(ValueError, "restart command must include port 4327"):
            control_server.validate_project({
                **validated,
                "restartCommand": "PORT=9998 npm run restart",
            })

    def test_optional_project_hook_is_logged_and_checked(self) -> None:
        project = {
            "id": "hook-project",
            "setupCommand": "printf 'setup complete\\n'",
        }

        control_server.run_project_hook(project, "setupCommand", "Setup", timeout=2)
        self.assertIn("setup complete", control_server.last_log_line("hook-project"))

        project["setupCommand"] = "exit 7"
        with self.assertRaisesRegex(ValueError, "status 7"):
            control_server.run_project_hook(project, "setupCommand", "Setup", timeout=2)

    def test_project_inspection_rejects_relative_or_missing_paths(self) -> None:
        with self.assertRaisesRegex(ValueError, "full project folder path"):
            control_server.inspect_project({"path": "relative/path", "port": 4325})
        with self.assertRaisesRegex(ValueError, "could not be found"):
            control_server.inspect_project({"path": str(self.root / "missing"), "port": 4325})
        with self.assertRaisesRegex(ValueError, "specific project folder"):
            control_server.inspect_project({"path": str(Path.home()), "port": 4325})

    @unittest.skipUnless(sys.platform == "darwin", "folder browsing uses macOS osascript")
    def test_folder_picker_returns_only_the_user_selected_folder(self) -> None:
        selected = self.root / "selected-project"
        selected.mkdir()
        completed = subprocess.CompletedProcess(
            args=["/usr/bin/osascript"],
            returncode=0,
            stdout=f"{selected}\n",
            stderr="",
        )
        with mock.patch.object(control_server.subprocess, "run", return_value=completed) as run:
            result = control_server.choose_project_folder()

        self.assertEqual(result, {"cancelled": False, "path": str(selected.resolve())})
        self.assertEqual(run.call_args.args[0][0], "/usr/bin/osascript")

        control_server.LAST_ACTIONS.clear()
        cancelled = subprocess.CompletedProcess(
            args=["/usr/bin/osascript"],
            returncode=1,
            stdout="",
            stderr="execution error: User canceled. (-128)\n",
        )
        with mock.patch.object(control_server.subprocess, "run", return_value=cancelled):
            self.assertEqual(control_server.choose_project_folder(), {"cancelled": True})

    def test_native_apps_are_verified_for_the_current_instance(self) -> None:
        source = self.root / "Control Module"
        settings = self.root / "settings"
        setup_app = source / "Setup.app" / "Contents"
        source.mkdir(parents=True)
        settings.mkdir(parents=True)
        setup_app.mkdir(parents=True)
        instance_id = "12345678-1234-4123-8123-123456789abc"
        (source / "package.json").write_text('{"name":"control-module"}\n', encoding="utf-8")
        (source / ".control-module-instance").write_text(f"{instance_id}\n", encoding="utf-8")
        (settings / "instance-id").write_text(f"{instance_id}\n", encoding="utf-8")
        (settings / "desktop-access").write_text("private\n", encoding="utf-8")
        (settings / "install-path").write_text(f"{source / 'Control Module.app'}\n", encoding="utf-8")
        (setup_app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "io.github.mitchell-mos.control-module.setup",
        }))

        environment = {
            "CONTROL_MODULE_INSTANCE_ID": instance_id,
            "CONTROL_MODULE_SOURCE_DIR": str(source),
            "CONTROL_MODULE_CONFIG_DIR": str(settings),
        }
        previous = {key: os.environ.get(key) for key in environment}
        try:
            os.environ.update(environment)
            self.assertEqual(control_server.verified_native_app_path("settings"), (source / "Setup.app").resolve())
            view = control_server.system_settings_view()
            self.assertEqual(view["desktopAccess"], "private")
            self.assertEqual(view["installLocation"], "Control Module folder")
            self.assertTrue(view["settingsAvailable"] if sys.platform == "darwin" else not view["settingsAvailable"])

            (setup_app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "example.invalid",
            }))
            self.assertIsNone(control_server.verified_native_app_path("settings"))
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

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
