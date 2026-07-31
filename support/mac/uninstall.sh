#!/bin/zsh

set -euo pipefail
umask 077

DEFAULT_CONFIG_DIR="$HOME/Library/Application Support/Control Module"
CONFIG_DIR="${CONTROL_MODULE_CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
SOURCE_DIR=""
REMOVE_SOURCE=0
DRY_RUN=0
STOP_ONLY=0
WEB_PORT=1025
RUNNER_URL="http://127.0.0.1:10001"
CLEANUP_SERVER="${0:A:h}/clear.py"

usage() {
  print -- "Usage: $0 [--source DIR] [--remove-source] [--dry-run] [--stop-only]"
}

while (( $# > 0 )); do
  case "$1" in
    --source)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      SOURCE_DIR="$2"
      shift 2
      ;;
    --remove-source)
      REMOVE_SOURCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --stop-only)
      STOP_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      print -u2 -- "Unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SOURCE_DIR" && -r "$CONFIG_DIR/project-path" ]]; then
  IFS= read -r SOURCE_DIR < "$CONFIG_DIR/project-path" || true
fi
[[ -n "$SOURCE_DIR" ]] && SOURCE_DIR="${SOURCE_DIR:A}"
CONFIG_DIR="${CONFIG_DIR:A}"
DEFAULT_CONFIG_DIR="${DEFAULT_CONFIG_DIR:A}"

if [[ "$CONFIG_DIR" != "$DEFAULT_CONFIG_DIR" || "${CONFIG_DIR:t}" != "Control Module" || "$CONFIG_DIR" == "/" || "$CONFIG_DIR" == "$HOME" ]]; then
  print -u2 -- "Refusing to remove an unexpected settings directory: $CONFIG_DIR"
  exit 1
fi

if [[ -r "$CONFIG_DIR/web-port" ]]; then
  IFS= read -r WEB_PORT < "$CONFIG_DIR/web-port" || true
fi
if [[ "$WEB_PORT" != <-> ]] || (( WEB_PORT < 1025 || WEB_PORT > 65535 || WEB_PORT == 10001 )); then
  print -u2 -- "The saved dashboard port is invalid. Nothing was removed."
  exit 1
fi
WEB_URL="http://127.0.0.1:$WEB_PORT/"

process_using_source() {
  local process_id="$1"
  local process_cwd
  [[ -n "$SOURCE_DIR" ]] || return 1
  process_cwd="$(/usr/sbin/lsof -a -p "$process_id" -d cwd -Fn 2>/dev/null | /usr/bin/sed -n 's/^n//p' | /usr/bin/head -1 || true)"
  [[ -n "$process_cwd" && "${process_cwd:A}" == "$SOURCE_DIR" ]]
}

wait_for_listener_to_stop() {
  local port="$1"
  local attempt
  for attempt in {1..60}; do
    /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || return 0
    /bin/sleep 0.1
  done
  return 1
}

stop_control_module() {
  local token=""
  local runner_pid=""
  local dashboard_pid=""
  local runner_verified=0
  local dashboard_verified=0

  [[ -r "$CONFIG_DIR/data/runtime/session-token" ]] && token="$(/usr/bin/tr -d '\r\n' < "$CONFIG_DIR/data/runtime/session-token")"
  runner_pid="$(/usr/sbin/lsof -tiTCP:10001 -sTCP:LISTEN 2>/dev/null | /usr/bin/head -1 || true)"
  dashboard_pid="$(/usr/sbin/lsof -tiTCP:"$WEB_PORT" -sTCP:LISTEN 2>/dev/null | /usr/bin/head -1 || true)"

  if [[ -n "$runner_pid" ]]; then
    if [[ -n "$token" ]] && /usr/bin/curl -fsS -H "X-Control-Token: $token" "$RUNNER_URL/health" 2>/dev/null | /usr/bin/grep -q '"ok": true'; then
      runner_verified=1
    elif process_using_source "$runner_pid"; then
      runner_verified=1
    fi
    if (( ! runner_verified )); then
      print -u2 -- "Port 10001 is in use by a process that could not be verified as Control Module. Nothing was removed."
      return 1
    fi
  fi

  if [[ -n "$dashboard_pid" ]]; then
    if /usr/bin/curl -fsS "$WEB_URL" 2>/dev/null | /usr/bin/grep -q "Control Module"; then
      dashboard_verified=1
    elif process_using_source "$dashboard_pid"; then
      dashboard_verified=1
    fi
    if (( ! dashboard_verified )); then
      print -u2 -- "Port $WEB_PORT is in use by a process that could not be verified as Control Module. Nothing was removed."
      return 1
    fi
  fi

  if (( runner_verified )) && [[ -n "$token" ]]; then
    /usr/bin/curl -fsS -X POST \
      -H "Origin: http://127.0.0.1:$WEB_PORT" \
      -H "Content-Type: application/json" \
      -H "X-Control-Token: $token" \
      --data '{}' \
      "$RUNNER_URL/api/projects/stop-all" >/dev/null 2>&1 || {
        /bin/sleep 1
        /usr/bin/curl -fsS -X POST \
          -H "Origin: http://127.0.0.1:$WEB_PORT" \
          -H "Content-Type: application/json" \
          -H "X-Control-Token: $token" \
          --data '{}' \
          "$RUNNER_URL/api/projects/stop-all" >/dev/null 2>&1 || true
      }
  fi

  if (( runner_verified )); then
    /bin/kill -TERM "$runner_pid" 2>/dev/null || true
    wait_for_listener_to_stop 10001 || {
      print -u2 -- "The Control Module runner did not stop safely. Nothing was removed."
      return 1
    }
  fi

  if (( dashboard_verified )); then
    /bin/kill -TERM "$dashboard_pid" 2>/dev/null || true
    wait_for_listener_to_stop "$WEB_PORT" || {
      print -u2 -- "The Control Module dashboard did not stop safely. Nothing was removed."
      return 1
    }
  fi
}

clear_browser_data_for_port() {
  local browser_port="$1"
  local python
  local cleanup_pid
  local attempt

  python="$(command -v python3 || true)"
  if [[ -z "$python" || ! -f "$CLEANUP_SERVER" ]]; then
    print -u2 -- "Browser data cleanup is unavailable, so nothing was removed."
    return 1
  fi
  if /usr/sbin/lsof -nP -iTCP:"$browser_port" -sTCP:LISTEN >/dev/null 2>&1; then
    print -u2 -- "Port $browser_port did not close, so browser data could not be cleared. Nothing was removed."
    return 1
  fi

  "$python" -B "$CLEANUP_SERVER" --port "$browser_port" >/dev/null 2>&1 &
  cleanup_pid=$!
  for attempt in {1..40}; do
    /usr/sbin/lsof -nP -iTCP:"$browser_port" -sTCP:LISTEN >/dev/null 2>&1 && break
    /bin/sleep 0.05
  done
  if ! /usr/sbin/lsof -nP -iTCP:"$browser_port" -sTCP:LISTEN >/dev/null 2>&1; then
    /bin/kill -TERM "$cleanup_pid" 2>/dev/null || true
    wait "$cleanup_pid" 2>/dev/null || true
    print -u2 -- "The local browser cleanup page could not start. Nothing was removed."
    return 1
  fi

  if ! /usr/bin/open "http://127.0.0.1:$browser_port/clear-control-module-data" >/dev/null 2>&1 \
    || ! /usr/bin/open "http://localhost:$browser_port/clear-control-module-data" >/dev/null 2>&1; then
    /bin/kill -TERM "$cleanup_pid" 2>/dev/null || true
    wait "$cleanup_pid" 2>/dev/null || true
    print -u2 -- "The browser cleanup pages could not be opened. Nothing was removed."
    return 1
  fi
  if ! wait "$cleanup_pid" 2>/dev/null; then
    print -u2 -- "The browser did not confirm cleanup for both local hostnames. Nothing was removed."
    return 1
  fi
}

clear_browser_data() {
  clear_browser_data_for_port "$WEB_PORT"
  if [[ "$WEB_PORT" != "1025" ]]; then
    clear_browser_data_for_port 1025
  fi
}

is_control_module_app() {
  local app_path="$1"
  local identifier
  [[ -d "$app_path/Contents" ]] || return 1
  identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$identifier" == "io.github.mitchell-mos.control-module" || "$identifier" == "local.codex.control-module" ]]
}

remove_installed_app() {
  local app_path="$1"
  [[ -n "$app_path" ]] || return 0
  if [[ "${app_path:t}" != "Control Module.app" ]]; then
    print -u2 -- "Refusing to remove an unexpected app path: $app_path"
    return 1
  fi
  if [[ -L "$app_path" ]]; then
    /bin/rm "$app_path"
  elif [[ -e "$app_path" ]]; then
    if ! is_control_module_app "$app_path"; then
      print -u2 -- "Refusing to remove an app that could not be verified as Control Module: $app_path"
      return 1
    fi
    /bin/rm -rf "$app_path"
  fi
}

is_control_module_tool() {
  local app_path="$1"
  local identifier
  [[ -d "$app_path/Contents" ]] || return 1
  identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$identifier" == "io.github.mitchell-mos.control-module.setup" \
    || "$identifier" == "io.github.mitchell-mos.control-module.uninstall" ]]
}

remove_tool_app() {
  local app_path="$1"
  [[ -d "$app_path" ]] || return 0
  if [[ -n "$SOURCE_DIR" && "${app_path:A:h}" == "$SOURCE_DIR" ]]; then
    return 0
  fi
  if is_control_module_tool "$app_path"; then
    /bin/rm -rf "$app_path"
  fi
}

typeset -aU APP_TARGETS
APP_TARGETS=(
  "$HOME/Applications/Control Module.app"
  "$HOME/Desktop/Control Module.app"
)
typeset -aU TOOL_TARGETS
TOOL_TARGETS=(
  "$HOME/Desktop/Setup.app"
  "$HOME/Desktop/Control Module Setup.app"
  "$HOME/Desktop/Uninstall.app"
)
configured_install_path=""
if [[ -r "$CONFIG_DIR/install-path" ]]; then
  IFS= read -r configured_install_path < "$CONFIG_DIR/install-path" || true
  [[ -n "$configured_install_path" ]] && APP_TARGETS+=("$configured_install_path")
fi

if (( DRY_RUN )); then
  print -- "Control Module uninstall preview"
  print -- "Settings and private data: $CONFIG_DIR"
  print -- "Dashboard port and browser storage: $WEB_PORT"
  for app_path in "${APP_TARGETS[@]}"; do
    print -- "Installed app or shortcut: $app_path"
  done
  for app_path in "${TOOL_TARGETS[@]}"; do
    if is_control_module_tool "$app_path"; then
      print -- "Setup or uninstall app: $app_path"
    fi
  done
  if (( REMOVE_SOURCE )); then
    print -- "Source checkout to move to Trash: $SOURCE_DIR"
  else
    print -- "Source checkout to keep: $SOURCE_DIR"
  fi
  exit 0
fi

stop_control_module
if (( STOP_ONLY )); then
  print -- "Control Module and its managed projects were stopped safely."
  exit 0
fi
clear_browser_data

for app_path in "${APP_TARGETS[@]}"; do
  remove_installed_app "$app_path"
done
for app_path in "${TOOL_TARGETS[@]}"; do
  remove_tool_app "$app_path"
done

if [[ -e "$CONFIG_DIR" ]]; then
  /bin/rm -rf "$CONFIG_DIR"
fi

if (( REMOVE_SOURCE )); then
  if [[ -z "$SOURCE_DIR" || ! -f "$SOURCE_DIR/package.json" || ! -f "$SOURCE_DIR/ControlModule" ]]; then
    print -u2 -- "The source folder could not be verified, so it was left unchanged."
    exit 1
  fi
  case "$SOURCE_DIR" in
    /|"$HOME"|"$HOME/Desktop"|"$HOME/Desktop/Apps")
      print -u2 -- "Refusing to move a broad or unsafe source folder: $SOURCE_DIR"
      exit 1
      ;;
  esac
  TRASH_DIR="$HOME/.Trash"
  /bin/mkdir -p "$TRASH_DIR"
  SOURCE_TRASH_PATH="$TRASH_DIR/Control Module source $(/bin/date '+%Y-%m-%d %H.%M.%S')"
  [[ -e "$SOURCE_TRASH_PATH" ]] && SOURCE_TRASH_PATH="$SOURCE_TRASH_PATH $$"
  cd /
  /bin/mv "$SOURCE_DIR" "$SOURCE_TRASH_PATH"
  print -- "Control Module was removed. The source checkout was moved to: $SOURCE_TRASH_PATH"
else
  print -- "Control Module was removed. The source checkout was kept at: $SOURCE_DIR"
fi
