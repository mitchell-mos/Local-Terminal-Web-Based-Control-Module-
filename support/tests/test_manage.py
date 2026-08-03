import base64
import json
import os
import platform
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANAGER = ROOT / "support" / "mac" / "manage.sh"
INSTALLER = ROOT / "support" / "mac" / "install.sh"
UNINSTALLER = ROOT / "support" / "mac" / "uninstall.sh"
VERSION_HELPER = ROOT / "support" / "mac" / "version.sh"
MAC_ONLY = unittest.skipUnless(platform.system() == "Darwin", "macOS lifecycle helper")


def decode_status(output: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in output.splitlines():
        key, encoded = line.split("=", 1)
        fields[key] = base64.b64decode(encoded).decode("utf-8")
    return fields


@MAC_ONLY
class ManageScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="control-module-manage-test-")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.source = self.root / "download" / "Control Module"
        self.config_root = self.home / "Library" / "Application Support" / "Control Module"
        (self.source / "support" / "mac").mkdir(parents=True)
        (self.source / "server").mkdir(parents=True)
        self.home.mkdir(parents=True)
        (self.source / "package.json").write_text(
            json.dumps({"name": "control-module", "version": "1.3.0"}) + "\n",
            encoding="utf-8",
        )
        (self.source / "version.json").write_text(
            json.dumps({"major": 1, "update": 3, "fix": 0}) + "\n",
            encoding="utf-8",
        )
        launcher = self.source / "ControlModule"
        launcher.write_text("#!/bin/zsh\n", encoding="utf-8")
        launcher.chmod(0o755)
        (self.source / "server" / "control_server.py").write_text("# fixture\n", encoding="utf-8")
        shutil.copy2(MANAGER, self.source / "support" / "mac" / "manage.sh")
        shutil.copy2(UNINSTALLER, self.source / "support" / "mac" / "uninstall.sh")
        shutil.copy2(VERSION_HELPER, self.source / "support" / "mac" / "version.sh")
        (self.source / "support" / "mac" / "manage.sh").chmod(0o755)
        (self.source / "support" / "mac" / "uninstall.sh").chmod(0o755)
        self.environment = {
            **os.environ,
            "HOME": str(self.home),
            "CONTROL_MODULE_CONFIG_ROOT": str(self.config_root),
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_manager(
        self,
        action: str = "status",
        check: bool = True,
        environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/zsh", str(self.source / "support" / "mac" / "manage.sh"), action, "--source", str(self.source)],
            check=check,
            capture_output=True,
            text=True,
            env=environment or self.environment,
        )

    def test_status_describes_an_uninstalled_source(self) -> None:
        status = decode_status(self.run_manager().stdout)

        self.assertEqual(status["source_version"], "v1.03.0")
        self.assertEqual(status["configured"], "0")
        self.assertEqual(status["installed"], "0")
        self.assertEqual(status["dashboard_running"], "0")
        self.assertEqual(status["runner_running"], "0")
        self.assertEqual(status["web_port"], "1025")

    def test_status_distinguishes_installed_and_available_versions(self) -> None:
        instance_id = "12345678-1234-4123-8123-123456789abc"
        instance = self.config_root / "instances" / instance_id
        app = self.source / "Control Module.app"
        runtime = instance / "workspace"
        shortcut = self.home / "Desktop" / "Control Module.app"
        (app / "Contents" / "Resources").mkdir(parents=True)
        runtime.mkdir(parents=True)
        shortcut.parent.mkdir(parents=True)
        instance.mkdir(parents=True, exist_ok=True)
        (self.source / ".control-module-instance").write_text(instance_id + "\n", encoding="utf-8")
        (app / "Contents" / "Resources" / "instance-id").write_text(instance_id + "\n", encoding="utf-8")
        app_launcher = app / "Contents" / "Resources" / "ControlModule"
        app_launcher.write_text("#!/bin/zsh\n", encoding="utf-8")
        app_launcher.chmod(0o755)
        (runtime / "package.json").write_text(
            json.dumps({"name": "control-module", "version": "1.2.1"}) + "\n",
            encoding="utf-8",
        )
        shortcut.symlink_to(app)
        settings = {
            "project-path": self.source,
            "install-path": app,
            "runtime-path": runtime,
            "shortcut-path": shortcut,
            "instance-id": instance_id,
            "web-port": "12025",
            "runner-port": "12026",
            "desktop-access": "private",
        }
        for name, value in settings.items():
            (instance / name).write_text(str(value) + "\n", encoding="utf-8")

        status = decode_status(self.run_manager().stdout)

        self.assertEqual(status["configured"], "1")
        self.assertEqual(status["installed"], "1")
        self.assertEqual(status["source_version"], "v1.03.0")
        self.assertEqual(status["installed_version"], "v1.02.1")
        self.assertEqual(status["version_relation"], "newer")
        self.assertEqual(status["shortcut"], "1")
        self.assertEqual(status["web_port"], "12025")

        (self.source / "version.json").write_text(
            json.dumps({"major": 1, "update": 1, "fix": 9}) + "\n",
            encoding="utf-8",
        )
        (self.source / "package.json").write_text(
            json.dumps({"name": "control-module", "version": "1.1.9"}) + "\n",
            encoding="utf-8",
        )
        older_status = decode_status(self.run_manager().stdout)
        self.assertEqual(older_status["source_version"], "v1.01.9")
        self.assertEqual(older_status["installed_version"], "v1.02.1")
        self.assertEqual(older_status["version_relation"], "older")

        polluted_environment = {**self.environment}
        polluted_environment.pop("CONTROL_MODULE_CONFIG_ROOT")
        polluted_environment["CONTROL_MODULE_CONFIG_DIR"] = str(instance)
        polluted_status = decode_status(
            self.run_manager(environment=polluted_environment).stdout,
        )
        self.assertEqual(polluted_status["installed"], "1")
        self.assertEqual(polluted_status["installed_version"], "v1.02.1")

        stopped = self.run_manager("stop")
        self.assertIn("stopped safely", stopped.stdout)
        self.assertTrue(app.is_dir())
        self.assertTrue(runtime.is_dir())

    def test_start_requires_the_matching_installed_app(self) -> None:
        result = self.run_manager("start", check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not installed", result.stderr)

    def test_manager_requires_the_exact_package_identity(self) -> None:
        (self.source / "package.json").write_text(
            json.dumps({
                "name": "different-project",
                "description": 'text containing "name": "control-module" is not identity',
                "version": "1.3.0",
            }) + "\n",
            encoding="utf-8",
        )

        result = self.run_manager(check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a verified Control Module checkout", result.stderr)

    def test_installer_rejects_an_unrelated_app_destination(self) -> None:
        result = subprocess.run(
            [
                "/bin/zsh",
                str(INSTALLER),
                "--source",
                str(self.source),
                "--destination",
                str(self.root / "Unrelated.app"),
            ],
            check=False,
            capture_output=True,
            text=True,
            env=self.environment,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("only in this source folder or your personal Applications folder", result.stderr)
        self.assertFalse((self.root / "Unrelated.app").exists())

    def test_release_version_comparison_uses_numeric_order(self) -> None:
        def relation(candidate: str, installed: str) -> str:
            result = subprocess.run(
                [
                    "/bin/zsh",
                    "-c",
                    'source "$1"; control_module_version_relation "$2" "$3"',
                    "version-test",
                    str(VERSION_HELPER),
                    candidate,
                    installed,
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            return result.stdout.strip()

        self.assertEqual(relation("v9.00.0", "v8.99.999"), "newer")
        self.assertEqual(relation("v1.10.0", "v1.09.999"), "newer")
        self.assertEqual(relation("v1.03.10", "v1.03.9"), "newer")
        self.assertEqual(relation("v1.03.3", "v1.03.3"), "same")
        self.assertEqual(relation("v1.03.3", "v1.04.0"), "older")
        self.assertEqual(relation("1.03.3", "v1.04.0"), "unknown")

    def test_release_label_rejects_malformed_or_inconsistent_metadata(self) -> None:
        def label() -> subprocess.CompletedProcess[str]:
            return subprocess.run(
                [
                    "/bin/zsh",
                    "-c",
                    'source "$1"; control_module_version_label "$2"',
                    "version-test",
                    str(VERSION_HELPER),
                    str(self.source),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        (self.source / "version.json").write_text(
            json.dumps({"major": 1, "update": 100, "fix": 0}) + "\n",
            encoding="utf-8",
        )
        self.assertNotEqual(label().returncode, 0)

        (self.source / "version.json").write_text(
            json.dumps({"major": 1, "update": 4, "fix": 0}) + "\n",
            encoding="utf-8",
        )
        self.assertNotEqual(label().returncode, 0)

    def test_installer_rejects_an_older_download_before_replacing_files(self) -> None:
        instance_id = "12345678-1234-4123-8123-123456789abc"
        instance = self.config_root / "instances" / instance_id
        app = self.source / "Control Module.app"
        runtime = instance / "workspace"
        (app / "Contents" / "Resources").mkdir(parents=True)
        runtime.mkdir(parents=True)
        instance.mkdir(parents=True, exist_ok=True)
        (self.source / ".control-module-instance").write_text(instance_id + "\n", encoding="utf-8")
        (app / "Contents" / "Resources" / "instance-id").write_text(instance_id + "\n", encoding="utf-8")
        app_launcher = app / "Contents" / "Resources" / "ControlModule"
        app_launcher.write_text("#!/bin/zsh\n", encoding="utf-8")
        app_launcher.chmod(0o755)
        (runtime / "version.json").write_text(
            json.dumps({"major": 1, "update": 4, "fix": 0}) + "\n",
            encoding="utf-8",
        )
        settings = {
            "project-path": self.source,
            "install-path": app,
            "runtime-path": runtime,
            "instance-id": instance_id,
            "web-port": "12025",
            "runner-port": "12026",
            "desktop-access": "private",
        }
        for name, value in settings.items():
            (instance / name).write_text(str(value) + "\n", encoding="utf-8")

        result = subprocess.run(
            [
                "/bin/zsh",
                str(INSTALLER),
                "--source",
                str(self.source),
                "--destination",
                str(app),
                "--web-port",
                "12025",
                "--desktop-access",
                "private",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=self.environment,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("blocks downgrades", result.stderr)
        self.assertTrue(app.is_dir())
        self.assertEqual(
            json.loads((runtime / "version.json").read_text(encoding="utf-8"))["update"],
            4,
        )

        (self.source / "version.json").write_text(
            json.dumps({"major": 1, "update": 100, "fix": 0}) + "\n",
            encoding="utf-8",
        )
        malformed_result = subprocess.run(
            [
                "/bin/zsh",
                str(INSTALLER),
                "--source",
                str(self.source),
                "--destination",
                str(app),
                "--web-port",
                "12025",
                "--desktop-access",
                "private",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=self.environment,
        )

        self.assertNotEqual(malformed_result.returncode, 0)
        self.assertIn("could not verify", malformed_result.stderr)
        self.assertTrue(app.is_dir())


if __name__ == "__main__":
    unittest.main()
