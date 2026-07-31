#!/usr/bin/env python3
"""Local-only command runner for Control Module."""

from __future__ import annotations

import json
import os
import re
import secrets
import signal
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


HOST = "127.0.0.1"
PORT = 10001
MIN_PROJECT_PORT = 1026
MAX_PROJECT_PORT = 9999
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
PROJECT_DIR = Path(__file__).resolve().parent
PROJECTS_FILE = PROJECT_DIR / "control-projects.json"
LOG_DIR = PROJECT_DIR / "control-logs"
RUNTIME_DIR = PROJECT_DIR / ".control-runtime"
SESSION_TOKEN_FILE = RUNTIME_DIR / "session-token"
ALLOWED_ORIGINS = {
    "http://127.0.0.1:1025",
    "http://localhost:1025",
}
ALLOWED_HOSTS = {"127.0.0.1:10001", "localhost:10001"}
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
PROJECT_DATA_BACKUP: Path | None = None


class RateLimitError(Exception):
    """Raised when a project action is repeated too quickly."""


class ProjectDataError(Exception):
    """Raised when saved project data cannot be read safely."""


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
    ensure_private_directory(LOG_DIR)
    ensure_private_directory(RUNTIME_DIR)
    private_files = [PROJECTS_FILE, *LOG_DIR.glob("*.log*")]
    for path in private_files:
        if not path.is_file():
            continue
        try:
            path.chmod(0o600)
        except OSError:
            pass


def write_projects(projects: list[dict[str, Any]]) -> None:
    global PROJECT_DATA_BACKUP
    write_private_text(PROJECTS_FILE, json.dumps(projects, indent=2) + "\n")
    PROJECT_DATA_BACKUP = None


def preserve_corrupt_projects() -> Path | None:
    global PROJECT_DATA_BACKUP
    if PROJECT_DATA_BACKUP is not None:
        return PROJECT_DATA_BACKUP
    backup = PROJECTS_FILE.with_name(
        f"control-projects.corrupt-{time.strftime('%Y%m%d-%H%M%S')}.json"
    )
    try:
        backup.write_bytes(PROJECTS_FILE.read_bytes())
        backup.chmod(0o600)
    except OSError:
        return None
    PROJECT_DATA_BACKUP = backup
    return backup


def read_projects() -> list[dict[str, Any]]:
    with LOCK:
        if not PROJECTS_FILE.exists():
            projects = default_projects()
            write_projects(projects)
            return projects
        try:
            PROJECTS_FILE.chmod(0o600)
            data = json.loads(PROJECTS_FILE.read_text(encoding="utf-8"))
            if not isinstance(data, list):
                raise json.JSONDecodeError("Project data must be a list", "", 0)
            return data
        except (OSError, json.JSONDecodeError) as error:
            backup = preserve_corrupt_projects()
            backup_note = f" A private backup was saved as {backup.name}." if backup else ""
            raise ProjectDataError(
                "Saved projects could not be read and were left unchanged."
                + backup_note
                + " Restore valid JSON or replace the file with an empty JSON array ([])."
            ) from error


def validate_project(payload: dict[str, Any]) -> dict[str, Any]:
    project_id = str(payload.get("id", "")).strip()
    name = str(payload.get("name", "")).strip()
    host = str(payload.get("host", "")).strip()
    command = str(payload.get("command", "")).strip()

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
    if not MIN_PROJECT_PORT <= port <= MAX_PROJECT_PORT:
        raise ValueError("Enter a port from 1026 to 9999. Lower ports are reserved by the system.")
    if len(command) > 4096:
        raise ValueError("Keep the terminal command under 4,096 characters.")

    return {
        "id": project_id,
        "name": name,
        "host": host,
        "port": port,
        "command": command,
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
    try:
        result = subprocess.run(
            ["/usr/sbin/lsof", "-nP", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=1,
        )
    except (OSError, subprocess.TimeoutExpired):
        return set()
    groups: set[int] = set()
    for line in result.stdout.splitlines():
        if not line.isdigit():
            continue
        try:
            groups.add(os.getpgid(int(line)))
        except (OSError, ProcessLookupError):
            continue
    return groups


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
    if not MIN_PROJECT_PORT <= port <= MAX_PROJECT_PORT:
        return f"Port {port} is reserved by the system. Use a port from 1026 to 9999."

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
        return lines[-1][-320:] if lines else ""
    except OSError:
        return ""


def project_view(project: dict[str, Any]) -> dict[str, Any]:
    project_id = project["id"]
    process_alive = process_is_running(project_id)
    process = PROCESSES.get(project_id)
    running = bool(
        process_alive
        and process
        and port_is_open(str(project["host"]), int(project["port"]))
        and port_is_owned_by_process_group(int(project["port"]), process.pid)
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
                pass
            except OSError as error:
                errors.append(f"{project_id}: forced stop failed: {error}")

        stopped_ids: list[str] = []
        for project_id, process in active.items():
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
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
        origin = self.headers.get("Origin")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.end_headers()
        self.wfile.write(body)

    def read_payload(self) -> dict[str, Any]:
        if self.headers.get_content_type() != "application/json":
            raise ValueError("Requests must use JSON.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ValueError("The request size is invalid.") from error
        if length < 1 or length > 8192:
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
        origin = self.headers.get("Origin")
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
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
                    self.send_json(200, {"projects": [project_view(item) for item in read_projects()]})
            except ProjectDataError as error:
                self.send_json(500, {"error": str(error)})
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
            elif self.path == "/api/projects/save":
                self.save_project(payload)
            elif self.path == "/api/projects/delete":
                self.delete_project(payload)
            elif self.path == "/api/projects/start":
                self.start_project(payload)
            elif self.path == "/api/projects/restart":
                self.restart_project(payload)
            elif self.path == "/api/projects/stop":
                self.stop_project(payload)
            elif self.path == "/api/projects/stop-all":
                self.stop_all_projects()
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
                    or str(validated["command"]).strip()
                    != str(existing.get("command", "")).strip()
                )
                if immutable_fields_changed:
                    raise ValueError(
                        "Only the project name can be edited while it is running. "
                        "Stop it to change the port or command."
                    )
                validated = {
                    **validated,
                    "host": str(existing.get("host", validated["host"])),
                    "port": int(existing.get("port", validated["port"])),
                    "command": str(existing.get("command", validated["command"])),
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
            projects = [saved, *[item for item in projects if item.get("id") != saved["id"]]]
            write_projects(projects)
            PROCESS_ERRORS.pop(saved["id"], None)
            PROCESS_STOP_REASONS.pop(saved["id"], None)
        self.send_json(200, {"project": project_view(saved)})

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
        stop_process(project_id)
        if not wait_for_port_to_close(host, port):
            detail = f"The old host did not release {host}:{port}, so it was not restarted."
            PROCESS_ERRORS[project_id] = detail
            raise OSError(detail)
        self.launch_project(project_id)

    def launch_project(self, project_id: str) -> None:
        with LOCK:
            projects, project = self.find_project(project_id)
            command = str(project.get("command", "")).strip()
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

            log_file = open_private_log(project_id)
            log_file.write(
                f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] Project command started.\n".encode()
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
        stop_process(project_id)
        _, project = self.find_project(project_id)
        self.send_json(200, {"project": project_view(project)})

    def stop_all_projects(self) -> None:
        with LOCK:
            managed_ids = list(PROCESSES)
            enforce_action_rate_limit([*managed_ids, "system:stop-all"])
            stopped_ids, forced_ids, errors = stop_processes(managed_ids)
            projects = [project_view(project) for project in read_projects()]
        self.send_json(
            200,
            {
                "projects": projects,
                "stoppedIds": stopped_ids,
                "forcedIds": forced_ids,
                "errors": errors,
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
