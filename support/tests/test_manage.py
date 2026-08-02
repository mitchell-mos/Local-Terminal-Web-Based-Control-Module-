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
UNINSTALLER = ROOT / "support" / "mac" / "uninstall.sh"
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
        (self.source / "support" / "mac" / "manage.sh").chmod(0o755)
        (self.source / "support" / "mac" / "uninstall.sh").chmod(0o755)
        self.environment = {
            **os.environ,
            "HOME": str(self.home),
            "CONTROL_MODULE_CONFIG_ROOT": str(self.config_root),
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_manager(self, action: str = "status", check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/zsh", str(self.source / "support" / "mac" / "manage.sh"), action, "--source", str(self.source)],
            check=check,
            capture_output=True,
            text=True,
            env=self.environment,
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
        self.assertEqual(status["shortcut"], "1")
        self.assertEqual(status["web_port"], "12025")

        stopped = self.run_manager("stop")
        self.assertIn("stopped safely", stopped.stdout)
        self.assertTrue(app.is_dir())
        self.assertTrue(runtime.is_dir())

    def test_start_requires_the_matching_installed_app(self) -> None:
        result = self.run_manager("start", check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not installed", result.stderr)


if __name__ == "__main__":
    unittest.main()
