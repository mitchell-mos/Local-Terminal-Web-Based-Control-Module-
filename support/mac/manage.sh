#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
CONFIG_ROOT="${CONTROL_MODULE_CONFIG_ROOT:-${CONTROL_MODULE_CONFIG_DIR:-$HOME/Library/Application Support/Control Module}}"
SOURCE_DIR=""
ACTION="status"
INSTANCE_ID=""
CONFIG_DIR=""
RUNTIME_DIR=""
INSTALL_APP=""
WEB_PORT=1025
RUNNER_PORT=10001

usage() {
  print -- "Usage: $0 status|start|stop|restart --source DIR"
}

if (( $# > 0 )) && [[ "$1" != --* ]]; then
  ACTION="$1"
  shift
fi

while (( $# > 0 )); do
  case "$1" in
    --source)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      SOURCE_DIR="$2"
      shift 2
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

if [[ "$ACTION" != "status" && "$ACTION" != "start" && "$ACTION" != "stop" && "$ACTION" != "restart" ]]; then
  print -u2 -- "Choose status, start, stop, or restart."
  exit 2
fi
if [[ -z "$SOURCE_DIR" ]]; then
  print -u2 -- "A Control Module source folder is required."
  exit 2
fi

SOURCE_DIR="${SOURCE_DIR:A}"
CONFIG_ROOT="${CONFIG_ROOT:A}"
if [[ ! -f "$SOURCE_DIR/package.json" \
  || ! -x "$SOURCE_DIR/ControlModule" \
  || ! -f "$SOURCE_DIR/server/control_server.py" \
  || ! -x "$SCRIPT_DIR/uninstall.sh" ]] \
  || ! /usr/bin/grep -Eq '"name"[[:space:]]*:[[:space:]]*"control-module"' "$SOURCE_DIR/package.json"; then
  print -u2 -- "The source folder is not a verified Control Module checkout."
  exit 1
fi

instance_id_is_valid() {
  print -r -- "$1" | /usr/bin/grep -Eq '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
}

version_label() {
  local project_dir="$1"
  local major="" update="" fix="" package_version=""
  if [[ -r "$project_dir/version.json" ]]; then
    major="$(/usr/bin/plutil -extract major raw "$project_dir/version.json" 2>/dev/null || true)"
    update="$(/usr/bin/plutil -extract update raw "$project_dir/version.json" 2>/dev/null || true)"
    fix="$(/usr/bin/plutil -extract fix raw "$project_dir/version.json" 2>/dev/null || true)"
  fi
  if [[ "$major" != <-> || "$update" != <-> || "$fix" != <-> ]]; then
    package_version="$(/usr/bin/plutil -extract version raw "$project_dir/package.json" 2>/dev/null || true)"
    if print -r -- "$package_version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      major="${package_version%%.*}"
      package_version="${package_version#*.}"
      update="${package_version%%.*}"
      fix="${package_version##*.}"
    else
      return 1
    fi
  fi
  /usr/bin/printf 'v%s.%02d.%s' "$major" "$update" "$fix"
}

emit_value() {
  local key="$1"
  local value="$2"
  local encoded
  encoded="$(print -rn -- "$value" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')"
  print -r -- "$key=$encoded"
}

read_setting() {
  local name="$1"
  local value=""
  [[ -r "$CONFIG_DIR/$name" ]] || return 1
  IFS= read -r value < "$CONFIG_DIR/$name" || true
  [[ -n "$value" ]] || return 1
  print -r -- "$value"
}

app_instance_id() {
  local app_path="$1"
  local app_id=""
  [[ -r "$app_path/Contents/Resources/instance-id" ]] || return 1
  IFS= read -r app_id < "$app_path/Contents/Resources/instance-id" || true
  instance_id_is_valid "$app_id" || return 1
  print -r -- "$app_id"
}

listener_uses_instance() {
  local port="$1"
  local process_id process_cwd
  process_id="$(/usr/sbin/lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | /usr/bin/head -1 || true)"
  [[ -n "$process_id" ]] || return 1
  process_cwd="$(/usr/sbin/lsof -a -p "$process_id" -d cwd -Fn 2>/dev/null \
    | /usr/bin/sed -n 's/^n//p' | /usr/bin/head -1 || true)"
  [[ -n "$process_cwd" ]] || return 1
  process_cwd="${process_cwd:A}"
  [[ "$process_cwd" == "$SOURCE_DIR" || ( -n "$RUNTIME_DIR" && "$process_cwd" == "$RUNTIME_DIR" ) ]]
}

load_configuration() {
  local configured_source=""
  if [[ -r "$SOURCE_DIR/.control-module-instance" ]]; then
    IFS= read -r INSTANCE_ID < "$SOURCE_DIR/.control-module-instance" || true
  fi
  [[ -n "$INSTANCE_ID" ]] || return 0
  instance_id_is_valid "$INSTANCE_ID" || {
    print -u2 -- "This folder's private installation marker is invalid."
    return 1
  }

  CONFIG_DIR="$CONFIG_ROOT/instances/$INSTANCE_ID"
  [[ -r "$CONFIG_DIR/project-path" ]] || return 0
  IFS= read -r configured_source < "$CONFIG_DIR/project-path" || true
  [[ -n "$configured_source" && "${configured_source:A}" == "$SOURCE_DIR" ]] || return 0

  INSTALL_APP="$(read_setting install-path || true)"
  RUNTIME_DIR="$(read_setting runtime-path || true)"
  [[ -n "$INSTALL_APP" ]] && INSTALL_APP="${INSTALL_APP:A}"
  [[ -n "$RUNTIME_DIR" ]] && RUNTIME_DIR="${RUNTIME_DIR:A}"
  if [[ -n "$RUNTIME_DIR" && "$RUNTIME_DIR" != "$SOURCE_DIR" && "$RUNTIME_DIR" != "$CONFIG_DIR/workspace" ]]; then
    RUNTIME_DIR=""
  fi
  WEB_PORT="$(read_setting web-port || print 1025)"
  RUNNER_PORT="$(read_setting runner-port || print 10001)"
  [[ "$WEB_PORT" == <-> ]] && (( WEB_PORT >= 1025 && WEB_PORT <= 65535 )) || WEB_PORT=1025
  [[ "$RUNNER_PORT" == <-> ]] && (( RUNNER_PORT >= 1025 && RUNNER_PORT <= 65535 && RUNNER_PORT != WEB_PORT )) || RUNNER_PORT=10001
}

configuration_is_owned() {
  local configured_source=""
  [[ -n "$CONFIG_DIR" && -r "$CONFIG_DIR/project-path" ]] || return 1
  IFS= read -r configured_source < "$CONFIG_DIR/project-path" || true
  [[ -n "$configured_source" && "${configured_source:A}" == "$SOURCE_DIR" ]]
}

installation_is_valid() {
  local app_parent app_name
  [[ -n "$INSTANCE_ID" && -n "$INSTALL_APP" && -d "$INSTALL_APP" && ! -L "$INSTALL_APP" ]] || return 1
  app_parent="${INSTALL_APP:h}"
  app_name="${INSTALL_APP:t}"
  [[ "$app_parent" == "$SOURCE_DIR" || "$app_parent" == "$HOME/Applications" ]] || return 1
  print -r -- "$app_name" | /usr/bin/grep -Eq '^Control Module( [a-f0-9]{8})?\.app$' || return 1
  [[ "$(app_instance_id "$INSTALL_APP" || true)" == "$INSTANCE_ID" ]]
}

status_output() {
  local configured=0 installed=0 dashboard_running=0 runner_running=0 shortcut=0
  local desktop_access="private" shortcut_path="" source_version="Unknown" installed_version="Not installed"
  configuration_is_owned && configured=1
  installation_is_valid && installed=1
  listener_uses_instance "$WEB_PORT" && dashboard_running=1
  listener_uses_instance "$RUNNER_PORT" && runner_running=1
  source_version="$(version_label "$SOURCE_DIR" || print Unknown)"
  if (( installed )); then
    installed_version="$(version_label "$RUNTIME_DIR" 2>/dev/null || version_label "$SOURCE_DIR" 2>/dev/null || print Unknown)"
  fi
  if (( configured )); then
    desktop_access="$(read_setting desktop-access || print private)"
    [[ "$desktop_access" == "private" || "$desktop_access" == "desktop" ]] || desktop_access="private"
    shortcut_path="$(read_setting shortcut-path || true)"
    if [[ -n "$shortcut_path" && -L "$shortcut_path" && "${shortcut_path:A}" == "$INSTALL_APP" ]]; then
      shortcut=1
    fi
  fi

  emit_value source_path "$SOURCE_DIR"
  emit_value source_version "$source_version"
  emit_value configured "$configured"
  emit_value installed "$installed"
  emit_value installed_version "$installed_version"
  emit_value install_path "$INSTALL_APP"
  emit_value runtime_path "$RUNTIME_DIR"
  emit_value web_port "$WEB_PORT"
  emit_value runner_port "$RUNNER_PORT"
  emit_value desktop_access "$desktop_access"
  emit_value shortcut "$shortcut"
  emit_value dashboard_running "$dashboard_running"
  emit_value runner_running "$runner_running"
}

wait_until_running() {
  local attempt
  for attempt in {1..120}; do
    if listener_uses_instance "$WEB_PORT" && listener_uses_instance "$RUNNER_PORT"; then
      return 0
    fi
    /bin/sleep 0.25
  done
  return 1
}

stop_instance() {
  configuration_is_owned || return 0
  CONTROL_MODULE_CONFIG_ROOT="$CONFIG_ROOT" "$SCRIPT_DIR/uninstall.sh" --source "$SOURCE_DIR" --stop-only >/dev/null
}

start_instance() {
  installation_is_valid || {
    print -u2 -- "Control Module is not installed for this folder. Apply Setup first."
    return 1
  }
  if listener_uses_instance "$WEB_PORT" && listener_uses_instance "$RUNNER_PORT"; then
    return 0
  fi
  if listener_uses_instance "$WEB_PORT" || listener_uses_instance "$RUNNER_PORT"; then
    stop_instance
  fi
  /usr/bin/open "$INSTALL_APP"
  wait_until_running || {
    print -u2 -- "Control Module did not finish starting. Check its private dashboard and runner logs."
    return 1
  }
}

load_configuration

case "$ACTION" in
  status)
    status_output
    ;;
  stop)
    stop_instance
    print -- "Control Module stopped safely."
    ;;
  start)
    start_instance
    print -- "Control Module started."
    ;;
  restart)
    stop_instance
    start_instance
    print -- "Control Module restarted."
    ;;
esac
