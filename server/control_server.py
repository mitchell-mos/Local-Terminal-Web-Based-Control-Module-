#!/usr/bin/env python3
"""Local-only command runner for Control Module."""

from __future__ import annotations

import json
import os
import plistlib
import re
import secrets
import shlex
import signal
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


HOST = "127.0.0.1"
MIN_PROJECT_PORT = 1026
MAX_PROJECT_PORT = 9999
BROWSER_BLOCKED_PROJECT_PORTS = frozenset({
    1719,
    1720,
    1723,
    2049,
    3659,
    4045,
    5060,
    5061,
    6000,
    6566,
    6665,
    6666,
    6667,
    6668,
    6669,
    6697,
})
GRACEFUL_STOP_SECONDS = 5.0
PROJECT_START_TIMEOUT_SECONDS = 30.0
ACTION_RATE_LIMIT_SECONDS = 1.0
SESSION_CHECK_SECONDS = 5.0
SESSION_LOCK_TIMEOUT_SECONDS = 15 * 60
SESSION_SAFETY_STOP_REASON = "Stopped after this Mac was locked for 15 minutes."
LOG_MAX_BYTES = 2 * 1024 * 1024
LOG_BACKUP_COUNT = 3
REQUEST_TIMEOUT_SECONDS = 10.0
MAX_REQUEST_THREADS = 24
MAX_REQUEST_BODY_BYTES = 16 * 1024
MAX_PROJECTS_FILE_BYTES = 2 * 1024 * 1024
MAX_SAVED_PROJECTS = 100
MAX_PROJECT_PATH_LENGTH = 4096
MAX_PACKAGE_JSON_BYTES = 1024 * 1024
MAX_PROJECT_COMMAND_LENGTH = 4096
MAX_OPTIONAL_COMMAND_LENGTH = 2048
MAX_PUBLIC_URL_LENGTH = 2048
PROJECT_HOOK_TIMEOUT_SECONDS = 60.0
PROJECT_STOP_HOOK_TIMEOUT_SECONDS = 10.0


def configured_runner_port() -> int:
    """Read this instance's private runner port."""
    try:
        candidate = int(os.environ.get("CONTROL_MODULE_RUNNER_PORT", "10001"))
    except ValueError:
        return 10001
    if not 1025 <= candidate <= 65535:
        return 10001
    return candidate


PORT = configured_runner_port()


def configured_web_port() -> int:
    """Read the dashboard port while keeping direct runner launches safe."""
    try:
        candidate = int(os.environ.get("CONTROL_MODULE_WEB_PORT", "1025"))
    except ValueError:
        return 1025
    if not 1025 <= candidate <= 65535 or candidate == PORT:
        return 1025
    return candidate


WEB_PORT = configured_web_port()
PROJECT_DIR = Path(__file__).resolve().parents[1]
BROWSER_TAB_SCRIPT = PROJECT_DIR / "server" / "browser_tabs.jxa"
DEFAULT_DATA_DIR = PROJECT_DIR / ".control-module-data"
DATA_DIR = Path(os.environ.get("CONTROL_MODULE_DATA_DIR", DEFAULT_DATA_DIR)).expanduser().resolve()
PROJECTS_FILE = DATA_DIR / "projects.json"
LOG_DIR = DATA_DIR / "logs" / "projects"
RUNTIME_DIR = DATA_DIR / "runtime"
BACKUP_DIR = DATA_DIR / "backups"
SESSION_TOKEN_FILE = RUNTIME_DIR / "session-token"
DASHBOARD_LOOPBACK_ORIGIN = f"http://127.0.0.1:{WEB_PORT}"
DASHBOARD_LOCALHOST_ORIGIN = f"http://localhost:{WEB_PORT}"
ALLOWED_ORIGINS = {
    DASHBOARD_LOOPBACK_ORIGIN,
    DASHBOARD_LOCALHOST_ORIGIN,
}
ALLOWED_HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
PROJECT_FOLDER_ROOT = Path.home().resolve()
SAFE_ENVIRONMENT_KEYS = {
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "SHELL",
    "TERM",
    "TMPDIR",
    "TZ",
    "USER",
    "LOGNAME",
}
ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,100}$")
LOCK = threading.RLock()
PROCESSES: dict[str, subprocess.Popen[bytes]] = {}
PROCESS_ERRORS: dict[str, str] = {}
PROCESS_STOP_REASONS: dict[str, str] = {}
HEALTHY_PROJECTS: set[str] = set()
LAST_ACTIONS: dict[str, float] = {}
SESSION_TOKEN = ""
PROJECT_DATA_STATE: dict[str, Path | None] = {"backup": None}
NATIVE_APP_IDENTIFIERS = {
    "settings": "io.github.mitchell-mos.control-module.setup",
    "uninstall": "io.github.mitchell-mos.control-module.uninstall",
}
NATIVE_APP_NAMES = {
    "settings": "Setup.app",
    "uninstall": "Uninstall.app",
}


class RateLimitError(Exception):
    """Raised when a project action is repeated too quickly."""


class ProjectDataError(Exception):
    """Raised when saved project data cannot be read safely."""


def configured_instance_id() -> str:
    candidate = os.environ.get("CONTROL_MODULE_INSTANCE_ID", "").strip()
    if not re.fullmatch(
        r"[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}",
        candidate,
    ):
        return ""
    return candidate


def configured_source_dir() -> Path | None:
    candidate = os.environ.get("CONTROL_MODULE_SOURCE_DIR", "").strip()
    if not candidate:
        return None
    source = Path(candidate).expanduser().resolve()
    try:
        package = json.loads((source / "package.json").read_text(encoding="utf-8"))
        marker = (source / ".control-module-instance").read_text(encoding="utf-8").strip()
    except (OSError, json.JSONDecodeError):
        return None
    if package.get("name") != "control-module" or marker != configured_instance_id():
        return None
    return source


def configured_settings_dir() -> Path | None:
    candidate = os.environ.get("CONTROL_MODULE_CONFIG_DIR", "").strip()
    if not candidate:
        return None
    settings = Path(candidate).expanduser().resolve()
    try:
        saved_instance = (settings / "instance-id").read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if saved_instance != configured_instance_id():
        return None
    return settings


def verified_native_app_path(kind: str) -> Path | None:
    app_name = NATIVE_APP_NAMES.get(kind)
    expected_identifier = NATIVE_APP_IDENTIFIERS.get(kind)
    source = configured_source_dir()
    if not app_name or not expected_identifier or source is None:
        return None
    candidate = source / app_name
    if candidate.is_symlink() or not candidate.is_dir():
        return None
    try:
        info_path = candidate / "Contents" / "Info.plist"
        with info_path.open("rb") as info_file:
            info = plistlib.load(info_file)
    except (OSError, plistlib.InvalidFileException):
        return None
    if info.get("CFBundleIdentifier") != expected_identifier:
        return None
    return candidate


def read_private_setting(name: str, default: str = "") -> str:
    settings = configured_settings_dir()
    if settings is None:
        return default
    try:
        return (settings / name).read_text(encoding="utf-8").strip() or default
    except OSError:
        return default


def system_settings_view() -> dict[str, Any]:
    access_mode = read_private_setting("desktop-access", "private")
    if access_mode not in {"private", "desktop"}:
        access_mode = "private"
    shortcut_enabled = bool(read_private_setting("shortcut-path"))
    install_path = read_private_setting("install-path")
    install_location = "Personal Applications" if "/Applications/" in install_path else "Control Module folder"
    native_apps_configured = bool(configured_instance_id() and os.environ.get("CONTROL_MODULE_SOURCE_DIR", "").strip())
    return {
        "webPort": WEB_PORT,
        "desktopAccess": access_mode,
        "desktopShortcut": shortcut_enabled,
        "installLocation": install_location,
        "settingsAvailable": sys.platform == "darwin" and native_apps_configured,
        "uninstallAvailable": sys.platform == "darwin" and native_apps_configured,
    }


def open_verified_native_app(kind: str) -> None:
    if sys.platform != "darwin":
        raise OSError("Native Control Module settings are available only on macOS.")
    application = verified_native_app_path(kind)
    if application is None:
        raise ValueError(f"The verified {kind} app could not be found. Run Setup from this Control Module folder.")
    enforce_action_rate_limit([f"system:{kind}"])
    subprocess.run(
        ["/usr/bin/open", str(application)],
        check=True,
        timeout=10,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def choose_project_folder() -> dict[str, Any]:
    """Open a user-controlled macOS folder picker without scanning other folders."""
    if sys.platform != "darwin":
        raise OSError("Folder browsing is available only on macOS. Enter the path instead.")
    enforce_action_rate_limit(["system:choose-folder"])
    try:
        result = subprocess.run(
            [
                "/usr/bin/osascript",
                "-e",
                'POSIX path of (choose folder with prompt "Choose the project folder")',
            ],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired as error:
        raise OSError("The folder picker timed out. Enter the folder path instead.") from error
    if result.returncode != 0:
        if "-128" in result.stderr or "User canceled" in result.stderr:
            return {"cancelled": True}
        raise OSError("The macOS folder picker could not open. Enter the folder path instead.")
    selected = result.stdout.strip()
    if not selected:
        return {"cancelled": True}
    directory = validate_project_directory(selected)
    return {"cancelled": False, "path": str(directory)}


def project_browser_tabs(project_id: str, action: str) -> dict[str, Any]:
    """Find, refresh, or focus browser tabs for one saved local project."""
    if not ID_PATTERN.fullmatch(project_id):
        raise ValueError("The project ID is invalid.")
    if action not in {"detect", "refresh", "focus"}:
        raise ValueError("The browser tab action is invalid.")
    with LOCK:
        project = next(
            (item for item in read_projects() if item.get("id") == project_id),
            None,
        )
    if project is None:
        raise ValueError("That project could not be found.")
    port = int(project["port"])
    empty_result = {
        "available": False,
        "matched": 0,
        "refreshed": 0,
        "focused": 0,
        "permissionDenied": False,
        "browsers": [],
    }
    if sys.platform != "darwin" or not BROWSER_TAB_SCRIPT.is_file():
        return empty_result

    enforce_action_rate_limit([f"browser-tab:{project_id}:{action}"])
    try:
        completed = subprocess.run(
            [
                "/usr/bin/osascript",
                "-l",
                "JavaScript",
                str(BROWSER_TAB_SCRIPT),
                str(port),
                action,
            ],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        return empty_result

    combined_error = f"{completed.stdout}\n{completed.stderr}"
    if completed.returncode != 0:
        return {
            **empty_result,
            "permissionDenied": bool(
                "-1743" in combined_error
                or re.search(r"not authorized|not permitted", combined_error, re.IGNORECASE)
            ),
        }
    try:
        payload = json.loads(completed.stdout.strip())
    except (json.JSONDecodeError, TypeError):
        return empty_result
    if not isinstance(payload, dict):
        return empty_result

    browsers = payload.get("browsers", [])
    safe_browsers = [
        str(name)[:40]
        for name in browsers
        if isinstance(name, str) and name.strip()
    ][:6] if isinstance(browsers, list) else []

    def safe_count(name: str) -> int:
        try:
            return max(0, min(int(payload.get(name, 0)), 100))
        except (TypeError, ValueError):
            return 0

    return {
        "available": payload.get("available") is True,
        "matched": safe_count("matched"),
        "refreshed": safe_count("refreshed"),
        "focused": safe_count("focused"),
        "permissionDenied": payload.get("permissionDenied") is True,
        "browsers": safe_browsers,
    }


def validate_project_directory(raw_path: Any) -> Path:
    candidate = str(raw_path or "").strip()
    if not candidate:
        raise ValueError("Choose a project folder or enter its path.")
    if len(candidate) > MAX_PROJECT_PATH_LENGTH or "\x00" in candidate:
        raise ValueError("The project folder path is invalid.")
    expanded = os.path.expanduser(candidate)
    if not os.path.isabs(expanded):
        raise ValueError("Enter the full project folder path, starting with /.")
    try:
        safe_root = os.path.realpath(os.fspath(PROJECT_FOLDER_ROOT))
        resolved_path = os.path.realpath(expanded)
    except (OSError, RuntimeError) as error:
        raise ValueError("That project folder could not be found.") from error
    if resolved_path == safe_root:
        raise ValueError("Choose a specific project folder, not the whole Mac or home folder.")
    safe_prefix = safe_root.rstrip(os.sep) + os.sep
    if not resolved_path.startswith(safe_prefix):
        raise ValueError("Choose a project folder inside your home folder.")
    try:
        contained = os.path.commonpath((safe_root, resolved_path)) == safe_root
    except ValueError:
        contained = False
    if not contained:
        raise ValueError("Choose a project folder inside your home folder.")
    if not os.path.exists(resolved_path):
        raise ValueError("That project folder could not be found.")
    resolved = Path(resolved_path)
    if not resolved.is_dir():
        raise ValueError("The selected project path is not a folder.")
    return resolved


def read_project_manifest(directory: Path) -> dict[str, Any] | None:
    manifest_path = directory / "package.json"
    if not manifest_path.is_file():
        return None
    try:
        if manifest_path.stat().st_size > MAX_PACKAGE_JSON_BYTES:
            raise ValueError("package.json is too large to inspect safely.")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError("package.json contains invalid JSON. Fix it or use Advanced.") from error
    except OSError as error:
        raise ValueError("package.json could not be read. Check its permissions or use Advanced.") from error
    if not isinstance(manifest, dict):
        raise ValueError("package.json must contain a JSON object. Fix it or use Advanced.")
    return manifest


def project_name_suggestion(directory: Path, manifest: dict[str, Any] | None) -> str:
    package_name = str((manifest or {}).get("name", "")).strip()
    suggestion = package_name.rsplit("/", 1)[-1] if package_name else directory.name
    suggestion = re.sub(r"[\x00-\x1f\x7f]+", " ", suggestion).strip()
    return suggestion[:48] or "Local project"


def package_scripts(manifest: dict[str, Any] | None) -> dict[str, str]:
    scripts = (manifest or {}).get("scripts", {})
    if not isinstance(scripts, dict):
        return {}
    return {
        str(name): command
        for name, command in scripts.items()
        if isinstance(name, str) and isinstance(command, str) and name and command.strip()
    }


def package_dependencies(manifest: dict[str, Any] | None) -> set[str]:
    names: set[str] = set()
    for section in ("dependencies", "devDependencies", "peerDependencies"):
        dependencies = (manifest or {}).get(section, {})
        if isinstance(dependencies, dict):
            names.update(str(name).lower() for name in dependencies)
    return names


def matching_scripts(scripts: dict[str, str], pattern: re.Pattern[str]) -> list[str]:
    matches = [name for name, command in scripts.items() if pattern.search(command)]
    return sorted(matches, key=lambda name: (name not in {"dev", "start", "serve"}, name))


def detect_project_kind(manifest: dict[str, Any] | None) -> tuple[str, str, list[str]]:
    if manifest is None:
        return "static", "Static files", []
    scripts = package_scripts(manifest)
    dependencies = package_dependencies(manifest)
    next_scripts = matching_scripts(scripts, re.compile(r"(?:^|[\s/])next(?:[\s]|$)"))
    if next_scripts:
        return "next", "Next.js", next_scripts
    vite_scripts = matching_scripts(scripts, re.compile(r"(?:^|[\s/])(?:vite|astro)(?:[\s]|$)"))
    if vite_scripts:
        label = "Astro" if "astro" in dependencies else "Vite-compatible"
        return "vite", label, vite_scripts
    if scripts:
        ordered_scripts = sorted(
            scripts,
            key=lambda name: (name not in {"dev", "start", "serve"}, name),
        )
        return "package", "Package script", ordered_scripts
    return "unknown", "Unrecognized package", []


def detect_package_manager(directory: Path, manifest: dict[str, Any] | None = None) -> str:
    declared = str((manifest or {}).get("packageManager", "")).strip().lower()
    declared_name = declared.split("@", 1)[0]
    if declared_name in {"npm", "pnpm", "yarn", "bun"}:
        return declared_name
    if (directory / "pnpm-lock.yaml").is_file():
        return "pnpm"
    if (directory / "yarn.lock").is_file():
        return "yarn"
    if (directory / "bun.lock").is_file() or (directory / "bun.lockb").is_file():
        return "bun"
    return "npm"


def package_script_command(package_manager: str, script: str) -> str:
    quoted_script = shlex.quote(script)
    if package_manager == "yarn":
        return f"corepack yarn run {quoted_script}"
    if package_manager == "pnpm":
        return f"corepack pnpm run {quoted_script}"
    if package_manager == "bun":
        return f"bun run {quoted_script}"
    return f"npm run {quoted_script}"


def generated_project_command(
    directory: Path,
    kind: str,
    port: int,
    script: str = "",
    package_manager: str = "npm",
) -> str:
    quoted_directory = shlex.quote(str(directory))
    if kind == "static":
        return f"cd -- {quoted_directory} && python3 -m http.server {port} --bind 127.0.0.1"
    if kind == "vite":
        return (
            f"cd -- {quoted_directory} && {package_script_command(package_manager, script)} -- "
            f"--host 127.0.0.1 --port {port}"
        )
    if kind == "next":
        return (
            f"cd -- {quoted_directory} && {package_script_command(package_manager, script)} -- "
            f"--hostname 127.0.0.1 --port {port}"
        )
    if kind == "package":
        return (
            f"cd -- {quoted_directory} && PORT={port} HOST=127.0.0.1 "
            f"{package_script_command(package_manager, script)}"
        )
    return ""


def project_port_restriction_reason(port: int) -> str:
    if not MIN_PROJECT_PORT <= port <= MAX_PROJECT_PORT:
        return f"Port {port} is reserved by the system. Use a port from 1026 to 9999."
    if port in BROWSER_BLOCKED_PROJECT_PORTS:
        return f"Port {port} is blocked by browsers. Choose another port."
    return ""


def inspect_project(payload: dict[str, Any]) -> dict[str, Any]:
    directory = validate_project_directory(payload.get("path"))
    try:
        port = int(payload.get("port", 0))
    except (TypeError, ValueError) as error:
        raise ValueError("Enter a valid port from 1026 to 9999.") from error
    restriction = project_port_restriction_reason(port)
    if restriction:
        raise ValueError(restriction)

    requested_kind = str(payload.get("kind", "auto")).strip()
    if requested_kind not in {"auto", "static", "vite", "next", "package"}:
        raise ValueError(
            "Choose Auto-detect, Static files, Vite-compatible, Next.js, or Package script."
        )
    requested_script = str(payload.get("script", "")).strip()
    manifest = read_project_manifest(directory)
    package_manager = detect_package_manager(directory, manifest)
    detected_kind, detected_label, scripts = detect_project_kind(manifest)
    selected_kind = detected_kind if requested_kind == "auto" else requested_kind
    selected_label = {
        "static": "Static files",
        "vite": detected_label if detected_kind == "vite" else "Vite-compatible",
        "next": "Next.js",
        "package": "Package script",
        "unknown": "Unrecognized package",
    }.get(selected_kind, "Unrecognized package")

    available_kinds = [{"value": "static", "label": "Static files"}]
    if detected_kind in {"vite", "next", "package"}:
        available_kinds.insert(0, {"value": detected_kind, "label": detected_label})

    selected_script = ""
    if selected_kind in {"vite", "next", "package"}:
        if detected_kind != selected_kind or not scripts:
            raise ValueError(f"No compatible {selected_label} run script was found. Use Advanced instead.")
        if requested_script and requested_script not in scripts:
            raise ValueError("That package script is not available for this project type.")
        selected_script = requested_script or scripts[0]

    command = generated_project_command(
        directory,
        selected_kind,
        port,
        selected_script,
        package_manager,
    )
    if selected_kind == "unknown":
        message = "This package type was not recognized. Choose Static files or use Advanced."
    elif requested_kind == "auto":
        manager_note = f" with {package_manager}" if manifest is not None else ""
        message = f"Detected {detected_label}{manager_note}."
    else:
        message = f"Using {selected_label}."

    return {
        "path": str(directory),
        "suggestedName": project_name_suggestion(directory, manifest),
        "detectedKind": detected_kind,
        "detectedLabel": detected_label,
        "selectedKind": selected_kind,
        "selectedLabel": selected_label,
        "availableKinds": available_kinds,
        "scripts": scripts,
        "selectedScript": selected_script,
        "packageManager": package_manager if manifest is not None else "",
        "command": command,
        "message": message,
    }


def enforce_action_rate_limit(project_ids: list[str]) -> None:
    unique_ids = list(dict.fromkeys(project_ids))
    if not unique_ids:
        return

    with LOCK:
        current = time.monotonic()
        remaining = max(
            (
                ACTION_RATE_LIMIT_SECONDS - (current - LAST_ACTIONS.get(project_id, 0.0))
                for project_id in unique_ids
            ),
            default=0.0,
        )
        if remaining > 0:
            raise RateLimitError("Please wait one second before controlling that project again.")
        for project_id in unique_ids:
            LAST_ACTIONS[project_id] = current


def now_ms() -> int:
    return int(time.time() * 1000)


def default_projects() -> list[dict[str, Any]]:
    return []


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.chmod(0o700)
    except OSError:
        # Permission hardening is best-effort on filesystems that do not expose POSIX modes.
        pass


def write_private_text(path: Path, content: str) -> None:
    ensure_private_directory(path.parent)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        path.chmod(0o600)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            # os.replace() already moved the temporary file into place.
            pass


def ensure_session_token() -> str:
    global SESSION_TOKEN
    ensure_private_directory(RUNTIME_DIR)
    if SESSION_TOKEN:
        return SESSION_TOKEN
    try:
        saved = SESSION_TOKEN_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        saved = ""
    if len(saved) < 32:
        saved = secrets.token_urlsafe(32)
        write_private_text(SESSION_TOKEN_FILE, saved + "\n")
    else:
        try:
            SESSION_TOKEN_FILE.chmod(0o600)
        except OSError:
            # The token remains usable on filesystems without POSIX permission support.
            pass
    SESSION_TOKEN = saved
    return saved


def rotate_session_token() -> str:
    """Create a new browser authorization token for each runner process."""
    global SESSION_TOKEN
    SESSION_TOKEN = secrets.token_urlsafe(32)
    write_private_text(SESSION_TOKEN_FILE, SESSION_TOKEN + "\n")
    return SESSION_TOKEN


def secure_existing_runtime_files() -> None:
    """Tighten permissions on private files created by older releases."""
    ensure_private_directory(DATA_DIR)
    ensure_private_directory(LOG_DIR)
    ensure_private_directory(RUNTIME_DIR)
    ensure_private_directory(BACKUP_DIR)
    private_files = [PROJECTS_FILE, *LOG_DIR.glob("*.log*"), *BACKUP_DIR.glob("*.json")]
    for path in private_files:
        if not path.is_file():
            continue
        try:
            path.chmod(0o600)
        except OSError:
            # Continue when the underlying filesystem cannot tighten POSIX permissions.
            pass


def write_projects(projects: list[dict[str, Any]]) -> None:
    write_private_text(PROJECTS_FILE, json.dumps(projects, indent=2) + "\n")
    PROJECT_DATA_STATE["backup"] = None


def preserve_corrupt_projects() -> Path | None:
    existing_backup = PROJECT_DATA_STATE["backup"]
    if existing_backup is not None:
        return existing_backup
    ensure_private_directory(BACKUP_DIR)
    backup = BACKUP_DIR / (
        f"control-projects.corrupt-{time.strftime('%Y%m%d-%H%M%S')}.json"
    )
    try:
        backup.write_bytes(PROJECTS_FILE.read_bytes())
        backup.chmod(0o600)
    except OSError:
        return None
    PROJECT_DATA_STATE["backup"] = backup
    return backup


def read_projects() -> list[dict[str, Any]]:
    with LOCK:
        if not PROJECTS_FILE.exists():
            projects = default_projects()
            write_projects(projects)
            return projects
        try:
            PROJECTS_FILE.chmod(0o600)
            raw_data = PROJECTS_FILE.read_bytes()
            if len(raw_data) > MAX_PROJECTS_FILE_BYTES:
                raise ValueError("The saved project file is too large.")
            data = json.loads(raw_data)
            if not isinstance(data, list):
                raise ValueError("Saved projects must be a list.")
            if len(data) > MAX_SAVED_PROJECTS:
                raise ValueError(f"Save no more than {MAX_SAVED_PROJECTS} projects.")

            projects: list[dict[str, Any]] = []
            seen_ids: set[str] = set()
            seen_ports: set[int] = set()
            for index, project in enumerate(data, start=1):
                if not isinstance(project, dict):
                    raise ValueError(f"Saved project {index} must be an object.")
                validated = validate_project(project)
                created_at = project.get("createdAt")
                updated_at = project.get("updatedAt")
                if type(created_at) is not int or created_at < 0:
                    raise ValueError(f"Saved project {index} has an invalid creation date.")
                if type(updated_at) is not int or updated_at < created_at:
                    raise ValueError(f"Saved project {index} has an invalid update date.")
                project_id = str(validated["id"])
                port = int(validated["port"])
                if project_id in seen_ids:
                    raise ValueError(f"Saved project {index} duplicates project ID {project_id}.")
                if port in seen_ports:
                    raise ValueError(f"Saved project {index} duplicates port {port}.")
                seen_ids.add(project_id)
                seen_ports.add(port)
                projects.append({**validated, "createdAt": created_at, "updatedAt": updated_at})
            return projects
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            backup = preserve_corrupt_projects()
            backup_note = f" A private backup was saved as {backup.name}." if backup else ""
            raise ProjectDataError(
                "Saved projects could not be read and were left unchanged."
                + backup_note
                + " Restore valid JSON or replace the file with an empty JSON array ([])."
            ) from error


def reorder_project_records(
    projects: list[dict[str, Any]],
    requested_ids: Any,
) -> list[dict[str, Any]]:
    if not isinstance(requested_ids, list):
        raise ValueError("Project order must be a list of project IDs.")
    project_ids = [str(project_id).strip() for project_id in requested_ids]
    saved_ids = [str(project.get("id", "")).strip() for project in projects]
    valid_ids = all(ID_PATTERN.fullmatch(project_id) for project_id in project_ids)
    exact_membership = (
        len(project_ids) == len(saved_ids)
        and len(set(project_ids)) == len(project_ids)
        and set(project_ids) == set(saved_ids)
    )
    if not valid_ids or not exact_membership:
        raise ValueError("Project order must include each saved project exactly once.")
    projects_by_id = {str(project["id"]): project for project in projects}
    return [projects_by_id[project_id] for project_id in project_ids]


def validate_project(payload: dict[str, Any]) -> dict[str, Any]:
    project_id = str(payload.get("id", "")).strip()
    name = str(payload.get("name", "")).strip()
    host = str(payload.get("host", "")).strip()
    public_url = str(payload.get("publicUrl", "")).strip()
    command = str(payload.get("command", "")).strip()
    setup_command = str(payload.get("setupCommand", "")).strip()
    stop_command = str(payload.get("stopCommand", "")).strip()
    restart_command = str(payload.get("restartCommand", "")).strip()

    try:
        port = int(payload.get("port", 0))
    except (TypeError, ValueError) as error:
        raise ValueError("Enter a valid port from 1026 to 9999.") from error

    if not ID_PATTERN.fullmatch(project_id):
        raise ValueError("The project ID is invalid.")
    if not 1 <= len(name) <= 48:
        raise ValueError("Project names must be between 1 and 48 characters.")
    if host not in {"localhost", "127.0.0.1"}:
        raise ValueError("Choose localhost or 127.0.0.1.")
    if len(public_url) > MAX_PUBLIC_URL_LENGTH:
        raise ValueError(
            f"Keep the published-site address under {MAX_PUBLIC_URL_LENGTH:,} characters."
        )
    if public_url:
        try:
            parsed_public_url = urlsplit(public_url)
        except ValueError as error:
            raise ValueError("Enter a complete published-site address.") from error
        if parsed_public_url.scheme not in {"http", "https"}:
            raise ValueError("The published site must use http:// or https://.")
        if not parsed_public_url.hostname:
            raise ValueError("Enter a complete published-site address.")
        if parsed_public_url.username or parsed_public_url.password:
            raise ValueError(
                "The published-site address cannot contain a username or password."
            )
    restriction = project_port_restriction_reason(port)
    if restriction:
        raise ValueError(restriction)
    if len(command) > MAX_PROJECT_COMMAND_LENGTH:
        raise ValueError(
            f"Keep the start command under {MAX_PROJECT_COMMAND_LENGTH:,} characters."
        )
    for label, optional_command in (
        ("setup", setup_command),
        ("stop", stop_command),
        ("restart", restart_command),
    ):
        if len(optional_command) > MAX_OPTIONAL_COMMAND_LENGTH:
            raise ValueError(
                f"Keep the {label} command under {MAX_OPTIONAL_COMMAND_LENGTH:,} characters."
            )
    if command and not re.search(rf"(?<!\d){port}(?!\d)", command):
        raise ValueError(f"The start command must include port {port}.")
    if restart_command and not re.search(rf"(?<!\d){port}(?!\d)", restart_command):
        raise ValueError(f"The restart command must include port {port}.")

    return {
        "id": project_id,
        "name": name,
        "host": host,
        "port": port,
        "publicUrl": public_url,
        "command": command,
        "setupCommand": setup_command,
        "stopCommand": stop_command,
        "restartCommand": restart_command,
    }


def process_is_running(project_id: str) -> bool:
    process = PROCESSES.get(project_id)
    if process is None:
        return False
    return_code = process.poll()
    if return_code is None or process_group_is_running(process.pid):
        return True
    PROCESSES.pop(project_id, None)
    HEALTHY_PROJECTS.discard(project_id)
    PROCESS_STOP_REASONS.pop(project_id, None)
    detail = last_log_line(project_id)
    PROCESS_ERRORS[project_id] = (
        f"The command exited with status {return_code}. Last output: {detail}"
        if detail
        else f"The command exited with status {return_code}."
    )
    return False


def port_is_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.2):
            return True
    except OSError:
        return False


def wait_for_port_to_close(host: str, port: int, timeout: float = 2.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not port_is_open(host, port):
            return True
        time.sleep(0.05)
    return not port_is_open(host, port)


def listener_process_groups(port: int) -> set[int]:
    """Return process groups for listeners without ever signaling those listeners directly."""
    return listener_process_groups_by_port({port}).get(port, set())


def listener_process_groups_by_port(ports: set[int]) -> dict[int, set[int]]:
    """Read all requested listener owners from one lsof snapshot."""
    targets = {port for port in ports if MIN_PROJECT_PORT <= port <= MAX_PROJECT_PORT}
    if not targets:
        return {}
    try:
        result = subprocess.run(
            ["/usr/sbin/lsof", "-nP", "-Fpn", "-iTCP", "-sTCP:LISTEN"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=1,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}
    groups_by_port: dict[int, set[int]] = {}
    process_group: int | None = None
    for line in result.stdout.splitlines():
        if line.startswith("p") and line[1:].isdigit():
            try:
                process_group = os.getpgid(int(line[1:]))
            except (OSError, ProcessLookupError):
                process_group = None
            continue
        if not line.startswith("n") or process_group is None:
            continue
        match = re.search(r":(\d+)$", line[1:].split("->", 1)[0])
        if not match:
            continue
        port = int(match.group(1))
        if port in targets:
            groups_by_port.setdefault(port, set()).add(process_group)
    return groups_by_port


def port_is_owned_by_process_group(port: int, process_group_id: int) -> bool:
    return process_group_id in listener_process_groups(port)


def console_is_locked() -> bool | None:
    """Read macOS's console lock flag without relying on the web page staying open."""
    if sys.platform != "darwin":
        return False

    process: subprocess.Popen[str] | None = None
    try:
        process = subprocess.Popen(
            ["/usr/sbin/ioreg", "-n", "Root", "-d1"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        if process.stdout is None:
            return None
        for line in process.stdout:
            if '"IOConsoleLocked"' not in line:
                continue
            if "= Yes" in line:
                return True
            if "= No" in line:
                return False
            return None
    except OSError:
        return None
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=0.5)
    return None


def update_lock_timer(
    locked_since: float | None,
    locked: bool | None,
    current_time: float,
) -> tuple[float | None, bool]:
    if locked is False:
        return None, False
    if locked is None:
        return locked_since, False
    if locked_since is None:
        return current_time, False
    return locked_since, current_time - locked_since >= SESSION_LOCK_TIMEOUT_SECONDS


def replace_command_port(command: str, old_port: int, new_port: int) -> str:
    return re.sub(rf"\b{old_port}\b", str(new_port), command)


def project_port(project: dict[str, Any]) -> int | None:
    try:
        return int(project.get("port", 0))
    except (TypeError, ValueError):
        return None


def port_unavailable_reason(
    host: str,
    port: int,
    exclude_project_id: str | None = None,
) -> str:
    restriction = project_port_restriction_reason(port)
    if restriction:
        return restriction

    projects = read_projects()
    conflict = next(
        (
            project
            for project in projects
            if project.get("id") != exclude_project_id and project_port(project) == port
        ),
        None,
    )
    if conflict:
        return f"Port {port} is already assigned to {conflict.get('name', 'another project')}."

    if port_is_open(host, port):
        own_process = PROCESSES.get(exclude_project_id or "")
        own_project = next(
            (
                project
                for project in projects
                if project.get("id") == exclude_project_id and project_port(project) == port
            ),
            None,
        )
        if (
            own_project
            and own_process
            and process_group_is_running(own_process.pid)
            and exclude_project_id in HEALTHY_PROJECTS
            and port_is_owned_by_process_group(port, own_process.pid)
        ):
            return ""
        return f"Port {port} is already being used by another program."

    return ""


def find_available_port(host: str, starting_port: int, exclude_project_id: str | None = None) -> int | None:
    assigned_ports = {
        port
        for project in read_projects()
        if project.get("id") != exclude_project_id
        if (port := project_port(project)) is not None
    }
    first_port = max(MIN_PROJECT_PORT, min(starting_port + 1, MAX_PROJECT_PORT + 1))
    candidates = [
        *range(first_port, MAX_PROJECT_PORT + 1),
        *range(MIN_PROJECT_PORT, min(max(starting_port, MIN_PROJECT_PORT), MAX_PROJECT_PORT + 1)),
    ]
    for candidate in candidates:
        if project_port_restriction_reason(candidate):
            continue
        if candidate in assigned_ports:
            continue
        if not port_is_open(host, candidate):
            return candidate
    return None


def log_path(project_id: str) -> Path:
    return LOG_DIR / f"{project_id}.log"


def rotate_project_log(project_id: str) -> None:
    path = log_path(project_id)
    try:
        if path.stat().st_size < LOG_MAX_BYTES:
            return
    except FileNotFoundError:
        return
    for index in range(LOG_BACKUP_COUNT, 0, -1):
        source = path if index == 1 else path.with_suffix(f".log.{index - 1}")
        destination = path.with_suffix(f".log.{index}")
        if not source.exists():
            continue
        if index == LOG_BACKUP_COUNT and destination.exists():
            destination.unlink()
        os.replace(source, destination)


def open_private_log(project_id: str):
    ensure_private_directory(LOG_DIR)
    rotate_project_log(project_id)
    path = log_path(project_id)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        path.chmod(0o600)
    except OSError:
        # Logging should continue on filesystems that cannot change POSIX modes.
        pass
    return os.fdopen(descriptor, "ab")


def project_environment() -> dict[str, str]:
    environment = {
        key: value
        for key, value in os.environ.items()
        if key in SAFE_ENVIRONMENT_KEYS
    }
    environment["PATH"] = os.environ.get(
        "CONTROL_MODULE_PROJECT_PATH",
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    )
    environment["HOME"] = str(Path.home())
    environment["PYTHONUNBUFFERED"] = "1"
    return environment


def last_log_line(project_id: str) -> str:
    path = log_path(project_id)
    if not path.exists():
        return ""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        if not lines:
            return ""
        summary = lines[-1][-320:]
        summary = re.sub(
            r"(?i)\bAuthorization\s*([:=])\s*(?:Bearer\s+)?\S+",
            r"Authorization\1[redacted]",
            summary,
        )
        summary = re.sub(
            r"(?i)\b(api[_-]?key|password|secret|token)\s*([:=])\s*\S+",
            r"\1\2[redacted]",
            summary,
        )
        return re.sub(r"(?i)\bBearer\s+\S+", "Bearer [redacted]", summary)
    except OSError:
        return ""


def run_project_hook(
    project: dict[str, Any],
    field: str,
    label: str,
    timeout: float = PROJECT_HOOK_TIMEOUT_SECONDS,
) -> None:
    """Run an optional user-saved lifecycle command with a bounded process group."""
    command = str(project.get(field, "")).strip()
    if not command:
        return

    project_id = str(project["id"])
    with open_private_log(project_id) as log_file:
        log_file.write(
            f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] {label} command started.\n".encode()
        )
        log_file.flush()
        process = subprocess.Popen(
            ["/bin/zsh", "-c", command],
            cwd=PROJECT_DIR,
            env=project_environment(),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            return_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=2)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    # The process group may exit between the timeout and forced-stop attempt.
                    pass
                process.wait(timeout=2)
            raise ValueError(
                f"The {label.lower()} command timed out after {int(timeout)} seconds."
            ) from error

    if return_code != 0:
        detail = last_log_line(project_id)
        suffix = f" Last output: {detail}" if detail else ""
        raise ValueError(
            f"The {label.lower()} command exited with status {return_code}.{suffix}"
        )


def project_view(
    project: dict[str, Any],
    listener_groups: dict[int, set[int]] | None = None,
) -> dict[str, Any]:
    project_id = project["id"]
    process_alive = process_is_running(project_id)
    process = PROCESSES.get(project_id)
    port = int(project["port"])
    if listener_groups is None:
        listener_groups = listener_process_groups_by_port({port})
    running = bool(
        process_alive
        and process
        and port_is_open(str(project["host"]), port)
        and process.pid in listener_groups.get(port, set())
    )
    if running:
        HEALTHY_PROJECTS.add(project_id)
        PROCESS_ERRORS.pop(project_id, None)
        PROCESS_STOP_REASONS.pop(project_id, None)
    elif process_alive and project_id in HEALTHY_PROJECTS:
        HEALTHY_PROJECTS.discard(project_id)
        PROCESS_ERRORS[project_id] = (
            f"Nothing is responding at {project['host']}:{project['port']}."
        )
    return {
        **project,
        "running": running,
        **({"pid": process.pid} if running and process else {}),
        "lastLog": "" if running else PROCESS_ERRORS.get(project_id, ""),
        **(
            {"stopReason": PROCESS_STOP_REASONS[project_id]}
            if not running and project_id in PROCESS_STOP_REASONS
            else {}
        ),
    }


def project_views(projects: list[dict[str, Any]]) -> list[dict[str, Any]]:
    ports = {int(project["port"]) for project in projects}
    listener_groups = listener_process_groups_by_port(ports)
    return [project_view(project, listener_groups) for project in projects]


def process_group_is_running(process_group_id: int) -> bool:
    try:
        os.killpg(process_group_id, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def stop_processes(
    project_ids: list[str],
    reason: str | None = None,
) -> tuple[list[str], list[str], list[str]]:
    with LOCK:
        active: dict[str, subprocess.Popen[bytes]] = {}
        errors: list[str] = []
        forced_ids: list[str] = []

        for project_id in dict.fromkeys(project_ids):
            PROCESS_ERRORS.pop(project_id, None)
            HEALTHY_PROJECTS.discard(project_id)
            process = PROCESSES.get(project_id)
            if process is None or not process_group_is_running(process.pid):
                PROCESSES.pop(project_id, None)
                if reason is None:
                    PROCESS_STOP_REASONS.pop(project_id, None)
                continue
            active[project_id] = process

        for project_id, process in active.items():
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                # The process group exited between the ownership check and the signal.
                pass
            except OSError as error:
                errors.append(f"{project_id}: graceful stop failed: {error}")

        deadline = time.monotonic() + GRACEFUL_STOP_SECONDS
        remaining = dict(active)
        while remaining and time.monotonic() < deadline:
            for project_id, process in list(remaining.items()):
                process.poll()
                if not process_group_is_running(process.pid):
                    remaining.pop(project_id, None)
            if remaining:
                time.sleep(0.1)

        for project_id, process in remaining.items():
            forced_ids.append(project_id)
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                # The process group exited during the graceful-stop window.
                pass
            except OSError as error:
                errors.append(f"{project_id}: forced stop failed: {error}")

        stopped_ids: list[str] = []
        for project_id, process in active.items():
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                # The ownership check below decides whether the group still needs attention.
                pass
            if process_group_is_running(process.pid):
                errors.append(f"{project_id}: the managed process group did not exit")
                continue
            PROCESSES.pop(project_id, None)
            stopped_ids.append(project_id)
            if reason:
                PROCESS_STOP_REASONS[project_id] = reason
            else:
                PROCESS_STOP_REASONS.pop(project_id, None)

        return stopped_ids, forced_ids, errors


def stop_process(project_id: str) -> bool:
    stopped_ids, _, errors = stop_processes([project_id])
    if errors:
        raise OSError("; ".join(errors))
    return project_id in stopped_ids


def stop_all_processes(reason: str | None = None) -> None:
    stop_processes(list(PROCESSES), reason=reason)


def monitor_console_session(stop_event: threading.Event) -> None:
    locked_since: float | None = None
    while not stop_event.wait(SESSION_CHECK_SECONDS):
        locked_since, lock_expired = update_lock_timer(
            locked_since,
            console_is_locked(),
            time.monotonic(),
        )
        if lock_expired:
            stop_all_processes(reason=SESSION_SAFETY_STOP_REASON)


class ControlHandler(BaseHTTPRequestHandler):
    server_version = "ControlModule/1.0"

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(REQUEST_TIMEOUT_SECONDS)

    def log_message(self, format_string: str, *args: Any) -> None:
        return

    def host_allowed(self) -> bool:
        return self.headers.get("Host", "") in ALLOWED_HOSTS

    def origin_allowed(self, allow_missing: bool = False) -> bool:
        origin = self.headers.get("Origin")
        return (not origin and allow_missing) or origin in ALLOWED_ORIGINS

    def token_allowed(self) -> bool:
        supplied = self.headers.get("X-Control-Token", "")
        return bool(supplied and SESSION_TOKEN and secrets.compare_digest(supplied, SESSION_TOKEN))

    def request_allowed(self, allow_missing_origin: bool = False) -> bool:
        return (
            self.host_allowed()
            and self.origin_allowed(allow_missing=allow_missing_origin)
            and self.token_allowed()
        )

    def send_allowed_origin_header(self) -> None:
        origin = self.headers.get("Origin")
        if origin == DASHBOARD_LOOPBACK_ORIGIN:
            self.send_header("Access-Control-Allow-Origin", DASHBOARD_LOOPBACK_ORIGIN)
            self.send_header("Vary", "Origin")
        elif origin == DASHBOARD_LOCALHOST_ORIGIN:
            self.send_header("Access-Control-Allow-Origin", DASHBOARD_LOCALHOST_ORIGIN)
            self.send_header("Vary", "Origin")

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
        self.send_header("Cross-Origin-Resource-Policy", "same-site")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_allowed_origin_header()
        self.end_headers()
        self.wfile.write(body)

    def read_payload(self) -> dict[str, Any]:
        if self.headers.get_content_type() != "application/json":
            raise ValueError("Requests must use JSON.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ValueError("The request size is invalid.") from error
        if length < 1 or length > MAX_REQUEST_BODY_BYTES:
            raise ValueError("The request is empty or too large.")
        try:
            payload = json.loads(self.rfile.read(length))
        except json.JSONDecodeError as error:
            raise ValueError("The request contains invalid JSON.") from error
        if not isinstance(payload, dict):
            raise ValueError("The request must be a JSON object.")
        return payload

    def find_project(self, project_id: str) -> tuple[list[dict[str, Any]], dict[str, Any]]:
        projects = read_projects()
        project = next((item for item in projects if item.get("id") == project_id), None)
        if project is None:
            raise ValueError("That project could not be found.")
        return projects, project

    def do_OPTIONS(self) -> None:
        if not self.host_allowed() or not self.origin_allowed():
            self.send_json(403, {"error": "This runner only accepts requests from Control Module."})
            return
        self.send_response(204)
        self.send_allowed_origin_header()
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Control-Token")
        self.send_header("Access-Control-Max-Age", "600")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()

    def do_GET(self) -> None:
        if self.path == "/health":
            if not self.request_allowed(allow_missing_origin=True):
                self.send_json(403, {"error": "Invalid local session."})
                return
            self.send_json(200, {"ok": True})
            return
        if self.path == "/api/projects":
            if not self.request_allowed():
                self.send_json(403, {"error": "This runner only accepts requests from Control Module."})
                return
            try:
                with LOCK:
                    self.send_json(200, {"projects": project_views(read_projects())})
            except ProjectDataError as error:
                self.send_json(500, {"error": str(error)})
            return
        if self.path == "/api/system/settings":
            if not self.request_allowed():
                self.send_json(403, {"error": "This runner only accepts requests from Control Module."})
                return
            self.send_json(200, system_settings_view())
            return
        self.send_json(404, {"error": "Not found."})

    def do_POST(self) -> None:
        if not self.request_allowed():
            self.send_json(403, {"error": "This runner only accepts requests from Control Module."})
            return

        try:
            payload = self.read_payload()
            if self.path == "/api/ports/check":
                self.check_port(payload)
            elif self.path == "/api/projects/inspect":
                self.send_json(200, inspect_project(payload))
            elif self.path == "/api/system/choose-folder":
                self.send_json(200, choose_project_folder())
            elif self.path == "/api/projects/reorder":
                self.reorder_projects(payload)
            elif self.path == "/api/projects/save":
                self.save_project(payload)
            elif self.path == "/api/projects/delete":
                self.delete_project(payload)
            elif self.path == "/api/projects/start":
                self.start_project(payload)
            elif self.path == "/api/projects/restart":
                self.restart_project(payload)
            elif self.path == "/api/projects/browser-tabs":
                project_id = str(payload.get("id", "")).strip()
                action = str(payload.get("action", "detect")).strip()
                self.send_json(200, project_browser_tabs(project_id, action))
            elif self.path == "/api/projects/stop":
                self.stop_project(payload)
            elif self.path == "/api/projects/stop-all":
                self.stop_all_projects()
            elif self.path == "/api/system/open-settings":
                open_verified_native_app("settings")
                self.send_json(200, {"opened": True})
            elif self.path == "/api/system/open-uninstall":
                if payload.get("confirmed") is not True:
                    raise ValueError("Confirm before opening Uninstall.")
                open_verified_native_app("uninstall")
                self.send_json(200, {"opened": True})
            else:
                self.send_json(404, {"error": "Not found."})
        except RateLimitError as error:
            self.send_json(429, {"error": str(error), "retryAfterMs": 1000})
        except ProjectDataError as error:
            self.send_json(500, {"error": str(error)})
        except ValueError as error:
            self.send_json(400, {"error": str(error)})
        except OSError as error:
            print(f"Control Module operating system error: {error}", file=sys.stderr)
            self.send_json(500, {"error": "The local runner encountered an operating system error."})
        except Exception as error:
            print(f"Control Module unexpected {type(error).__name__}: {error}", file=sys.stderr)
            self.send_json(500, {"error": "The local runner encountered an unexpected error."})

    def check_port(self, payload: dict[str, Any]) -> None:
        host = str(payload.get("host", "")).strip()
        project_id = str(payload.get("projectId", "")).strip() or None
        if host not in {"localhost", "127.0.0.1"}:
            raise ValueError("Choose localhost or 127.0.0.1.")
        if project_id and not ID_PATTERN.fullmatch(project_id):
            raise ValueError("The project ID is invalid.")
        try:
            port = int(payload.get("port", 0))
        except (TypeError, ValueError) as error:
            raise ValueError("Enter a valid port.") from error

        reason = port_unavailable_reason(host, port, project_id)
        response: dict[str, Any] = {"available": not reason}
        if reason:
            response["reason"] = reason
            suggested_port = find_available_port(host, port, project_id)
            if suggested_port is not None:
                response["suggestedPort"] = suggested_port
        self.send_json(200, response)

    def save_project(self, payload: dict[str, Any]) -> None:
        validated = validate_project(payload)
        enforce_action_rate_limit([str(validated["id"])])
        with LOCK:
            projects = read_projects()
            existing = next((item for item in projects if item.get("id") == validated["id"]), None)
            existing_is_running = bool(existing and process_is_running(str(validated["id"])))
            if existing_is_running:
                immutable_fields_changed = (
                    str(validated["host"]) != str(existing.get("host", ""))
                    or int(validated["port"]) != project_port(existing)
                    or str(validated["publicUrl"]).strip()
                    != str(existing.get("publicUrl", "")).strip()
                    or str(validated["command"]).strip()
                    != str(existing.get("command", "")).strip()
                    or str(validated["setupCommand"]).strip()
                    != str(existing.get("setupCommand", "")).strip()
                    or str(validated["stopCommand"]).strip()
                    != str(existing.get("stopCommand", "")).strip()
                    or str(validated["restartCommand"]).strip()
                    != str(existing.get("restartCommand", "")).strip()
                )
                if immutable_fields_changed:
                    raise ValueError(
                        "Only the project name can be edited while it is running. "
                        "Stop it to change the port, published site, or process commands."
                    )
                validated = {
                    **validated,
                    "host": str(existing.get("host", validated["host"])),
                    "port": int(existing.get("port", validated["port"])),
                    "publicUrl": str(existing.get("publicUrl", "")),
                    "command": str(existing.get("command", validated["command"])),
                    "setupCommand": str(existing.get("setupCommand", "")),
                    "stopCommand": str(existing.get("stopCommand", "")),
                    "restartCommand": str(existing.get("restartCommand", "")),
                }
            else:
                reason = port_unavailable_reason(
                    str(validated["host"]),
                    int(validated["port"]),
                    str(validated["id"]) if existing else None,
                )
                if reason:
                    suggested_port = find_available_port(
                        str(validated["host"]),
                        int(validated["port"]),
                        str(validated["id"]) if existing else None,
                    )
                    suggestion = f" Try port {suggested_port}." if suggested_port is not None else ""
                    raise ValueError(reason + suggestion)
            timestamp = now_ms()
            saved = {
                **validated,
                "createdAt": existing.get("createdAt", timestamp) if existing else timestamp,
                "updatedAt": timestamp,
            }
            if existing:
                projects = [
                    saved if item.get("id") == saved["id"] else item
                    for item in projects
                ]
            else:
                projects = [saved, *projects]
            write_projects(projects)
            PROCESS_ERRORS.pop(saved["id"], None)
            PROCESS_STOP_REASONS.pop(saved["id"], None)
        self.send_json(200, {"project": project_view(saved)})

    def reorder_projects(self, payload: dict[str, Any]) -> None:
        with LOCK:
            projects = read_projects()
            reordered = reorder_project_records(projects, payload.get("ids"))
            write_projects(reordered)
        self.send_json(200, {"reordered": True})

    def delete_project(self, payload: dict[str, Any]) -> None:
        project_id = str(payload.get("id", "")).strip()
        if not ID_PATTERN.fullmatch(project_id):
            raise ValueError("The project ID is invalid.")
        enforce_action_rate_limit([project_id])
        stop_process(project_id)
        with LOCK:
            projects = [item for item in read_projects() if item.get("id") != project_id]
            write_projects(projects)
        self.send_json(200, {"deleted": True})

    def start_project(self, payload: dict[str, Any]) -> None:
        project_id = str(payload.get("id", "")).strip()
        if not ID_PATTERN.fullmatch(project_id):
            raise ValueError("The project ID is invalid.")
        enforce_action_rate_limit([project_id])
        self.launch_project(project_id)

    def restart_project(self, payload: dict[str, Any]) -> None:
        project_id = str(payload.get("id", "")).strip()
        if not ID_PATTERN.fullmatch(project_id):
            raise ValueError("The project ID is invalid.")
        enforce_action_rate_limit([project_id])
        _, project = self.find_project(project_id)
        host = str(project["host"])
        port = int(project["port"])
        hook_error: ValueError | None = None
        try:
            run_project_hook(
                project,
                "stopCommand",
                "Stop",
                PROJECT_STOP_HOOK_TIMEOUT_SECONDS,
            )
        except ValueError as error:
            hook_error = error
        stop_process(project_id)
        if not wait_for_port_to_close(host, port):
            detail = f"The old host did not release {host}:{port}, so it was not restarted."
            PROCESS_ERRORS[project_id] = detail
            raise OSError(detail)
        if hook_error is not None:
            PROCESS_ERRORS[project_id] = str(hook_error)
            raise hook_error
        self.launch_project(project_id, use_restart_command=True)

    def launch_project(self, project_id: str, use_restart_command: bool = False) -> None:
        with LOCK:
            _, project = self.find_project(project_id)
            command_field = (
                "restartCommand"
                if use_restart_command and str(project.get("restartCommand", "")).strip()
                else "command"
            )
            command = str(project.get(command_field, "")).strip()
            if not command:
                raise ValueError("Add a terminal command before starting this project.")
            PROCESS_ERRORS.pop(project_id, None)
            PROCESS_STOP_REASONS.pop(project_id, None)
            HEALTHY_PROJECTS.discard(project_id)
            if process_is_running(project_id):
                if port_is_open(str(project["host"]), int(project["port"])):
                    self.send_json(200, {"project": project_view(project)})
                    return
                stop_process(project_id)

            PROCESS_ERRORS.pop(project_id, None)
            HEALTHY_PROJECTS.discard(project_id)

            current_port = int(project["port"])
            reason = port_unavailable_reason(str(project["host"]), current_port, project_id)
            if reason:
                suggested_port = find_available_port(str(project["host"]), current_port, project_id)
                suggestion = (
                    f" Edit the project and switch to port {suggested_port}."
                    if suggested_port is not None
                    else " Edit the project and choose another port."
                )
                detail = reason + suggestion
                PROCESS_ERRORS[project_id] = detail
                raise ValueError(detail)

        try:
            run_project_hook(project, "setupCommand", "Setup")
        except ValueError as error:
            PROCESS_ERRORS[project_id] = str(error)
            raise

        with LOCK:
            _, project = self.find_project(project_id)
            command = str(project.get(command_field, "")).strip()
            current_port = int(project["port"])
            reason = port_unavailable_reason(str(project["host"]), current_port, project_id)
            if reason:
                detail = reason + " The setup command finished, but the project was not started."
                PROCESS_ERRORS[project_id] = detail
                raise ValueError(detail)
            log_file = open_private_log(project_id)
            log_file.write(
                f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] "
                f"{'Restart' if command_field == 'restartCommand' else 'Start'} command started.\n".encode()
            )
            log_file.flush()

            environment = project_environment()

            process = subprocess.Popen(
                ["/bin/zsh", "-c", command],
                cwd=PROJECT_DIR,
                env=environment,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            log_file.close()
            PROCESSES[project_id] = process

        deadline = time.monotonic() + PROJECT_START_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            if not process_is_running(project_id):
                detail = PROCESS_ERRORS.get(project_id, "The command exited immediately.")
                raise ValueError(detail)
            if port_is_open(str(project["host"]), int(project["port"])):
                if port_is_owned_by_process_group(int(project["port"]), process.pid):
                    self.send_json(200, {"project": project_view(project)})
                    return
            time.sleep(0.1)

        detail = (
            f"The command started, but its managed process group did not open "
            f"{project['host']}:{project['port']}."
        )
        stop_process(project_id)
        PROCESS_ERRORS[project_id] = detail
        raise ValueError(detail)

    def stop_project(self, payload: dict[str, Any]) -> None:
        project_id = str(payload.get("id", "")).strip()
        if not ID_PATTERN.fullmatch(project_id):
            raise ValueError("The project ID is invalid.")
        enforce_action_rate_limit([project_id])
        _, project = self.find_project(project_id)
        hook_error: ValueError | None = None
        try:
            run_project_hook(
                project,
                "stopCommand",
                "Stop",
                PROJECT_STOP_HOOK_TIMEOUT_SECONDS,
            )
        except ValueError as error:
            hook_error = error
        stop_process(project_id)
        if hook_error is not None:
            PROCESS_ERRORS[project_id] = str(hook_error)
            raise hook_error
        self.send_json(200, {"project": project_view(project)})

    def stop_all_projects(self) -> None:
        with LOCK:
            managed_ids = list(PROCESSES)
            projects_by_id = {
                str(project.get("id")): project
                for project in read_projects()
                if str(project.get("id")) in managed_ids
            }
        enforce_action_rate_limit([*managed_ids, "system:stop-all"])
        hook_errors: list[str] = []
        for project_id in managed_ids:
            project = projects_by_id.get(project_id)
            if project is None:
                continue
            try:
                run_project_hook(
                    project,
                    "stopCommand",
                    "Stop",
                    PROJECT_STOP_HOOK_TIMEOUT_SECONDS,
                )
            except ValueError as error:
                hook_errors.append(f"{project.get('name', project_id)}: {error}")
        with LOCK:
            stopped_ids, forced_ids, errors = stop_processes(managed_ids)
            projects = project_views(read_projects())
        self.send_json(
            200,
            {
                "projects": projects,
                "stoppedIds": stopped_ids,
                "forcedIds": forced_ids,
                "errors": [*hook_errors, *errors],
            },
        )


class BoundedThreadingHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = MAX_REQUEST_THREADS

    def __init__(self, server_address: tuple[str, int], handler_class: type[BaseHTTPRequestHandler]):
        self.request_slots = threading.BoundedSemaphore(MAX_REQUEST_THREADS)
        super().__init__(server_address, handler_class)

    def process_request(self, request: socket.socket, client_address: tuple[str, int]) -> None:
        if not self.request_slots.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.request_slots.release()
            raise

    def process_request_thread(self, request: socket.socket, client_address: tuple[str, int]) -> None:
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.request_slots.release()


def main() -> None:
    secure_existing_runtime_files()
    rotate_session_token()
    if PROJECTS_FILE.exists():
        try:
            PROJECTS_FILE.chmod(0o600)
        except OSError:
            # Startup can continue on filesystems without POSIX permission support.
            pass
    server = BoundedThreadingHTTPServer((HOST, PORT), ControlHandler)
    monitor_stop = threading.Event()
    monitor = threading.Thread(
        target=monitor_console_session,
        args=(monitor_stop,),
        name="control-module-session-monitor",
        daemon=True,
    )

    def shutdown(_signum: int, _frame: Any) -> None:
        monitor_stop.set()
        stop_all_processes()
        server.server_close()
        os._exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, shutdown)
    monitor.start()
    try:
        server.serve_forever()
    finally:
        monitor_stop.set()
        stop_all_processes()
        server.server_close()


if __name__ == "__main__":
    main()
