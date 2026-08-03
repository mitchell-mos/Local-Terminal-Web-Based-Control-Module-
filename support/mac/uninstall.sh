#!/bin/zsh

set -euo pipefail
umask 077

CONFIG_ROOT="${CONTROL_MODULE_CONFIG_ROOT:-$HOME/Library/Application Support/Control Module}"
CONFIG_DIR=""
SOURCE_DIR=""
REMOVE_SOURCE=0
DRY_RUN=0
STOP_ONLY=0
WEB_PORT=1025
RUNNER_PORT=10001
INSTANCE_ID=""
RUNTIME_DIR=""

usage() {
  print -- "Usage: $0 --source DIR [--remove-source] [--dry-run] [--stop-only]"
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

if [[ -z "$SOURCE_DIR" ]]; then
  print -u2 -- "A Control Module source folder is required. Nothing was changed."
  usage >&2
  exit 2
fi

SOURCE_DIR="${SOURCE_DIR:A}"
CONFIG_ROOT="${CONFIG_ROOT:A}"

if [[ ! -f "$SOURCE_DIR/package.json" \
  || ! -x "$SOURCE_DIR/ControlModule" \
  || ! -f "$SOURCE_DIR/server/control_server.py" \
  || ! -x "$SOURCE_DIR/support/mac/uninstall.sh" ]] \
  || ! /usr/bin/grep -Eq '"name"[[:space:]]*:[[:space:]]*"control-module"' "$SOURCE_DIR/package.json"; then
  print -u2 -- "The Control Module folder could not be verified. Nothing was changed."
  exit 1
fi

case "$SOURCE_DIR" in
  /|"$HOME"|"$HOME/Desktop"|"$HOME/Desktop/Apps")
    print -u2 -- "Refusing to operate on a broad or unsafe folder: $SOURCE_DIR"
    exit 1
    ;;
esac

if [[ -r "$SOURCE_DIR/.control-module-instance" ]]; then
  IFS= read -r INSTANCE_ID < "$SOURCE_DIR/.control-module-instance" || true
fi
if [[ -n "$INSTANCE_ID" ]] \
  && ! print -r -- "$INSTANCE_ID" | /usr/bin/grep -Eq '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'; then
  print -u2 -- "This folder's private installation marker is invalid. Nothing was changed."
  exit 1
fi
if [[ -n "$INSTANCE_ID" ]]; then
  CONFIG_DIR="$CONFIG_ROOT/instances/$INSTANCE_ID"
else
  CONFIG_DIR="$CONFIG_ROOT"
fi

if [[ ! -r "$CONFIG_DIR/project-path" && -r "$CONFIG_ROOT/project-path" ]]; then
  legacy_source=""
  IFS= read -r legacy_source < "$CONFIG_ROOT/project-path" || true
  if [[ -n "$legacy_source" && "${legacy_source:A}" == "$SOURCE_DIR" ]]; then
    CONFIG_DIR="$CONFIG_ROOT"
  fi
fi

if [[ -r "$CONFIG_DIR/instance-id" ]]; then
  configured_id=""
  IFS= read -r configured_id < "$CONFIG_DIR/instance-id" || true
  if [[ "$configured_id" != "$INSTANCE_ID" ]]; then
    print -u2 -- "This folder does not match its private installation settings. Nothing was changed."
    exit 1
  fi
fi

INSTANCE_IS_CONFIGURED=0
if [[ -r "$CONFIG_DIR/project-path" ]]; then
  configured_source=""
  IFS= read -r configured_source < "$CONFIG_DIR/project-path" || true
  if [[ -n "$configured_source" && "${configured_source:A}" == "$SOURCE_DIR" ]]; then
    INSTANCE_IS_CONFIGURED=1
  fi
fi

if (( INSTANCE_IS_CONFIGURED )) && [[ -r "$CONFIG_DIR/web-port" ]]; then
  IFS= read -r WEB_PORT < "$CONFIG_DIR/web-port" || true
fi
if (( INSTANCE_IS_CONFIGURED )) && [[ -r "$CONFIG_DIR/runner-port" ]]; then
  IFS= read -r RUNNER_PORT < "$CONFIG_DIR/runner-port" || true
fi
if (( INSTANCE_IS_CONFIGURED )) && [[ -r "$CONFIG_DIR/runtime-path" ]]; then
  IFS= read -r RUNTIME_DIR < "$CONFIG_DIR/runtime-path" || true
fi
[[ -n "$RUNTIME_DIR" ]] && RUNTIME_DIR="${RUNTIME_DIR:A}"
if [[ "$WEB_PORT" != <-> ]] || (( WEB_PORT < 1025 || WEB_PORT > 65535 )); then
  print -u2 -- "The configured dashboard port is invalid. Nothing was changed."
  exit 1
fi
if [[ "$RUNNER_PORT" != <-> ]] || (( RUNNER_PORT < 1025 || RUNNER_PORT > 65535 || RUNNER_PORT == WEB_PORT )); then
  print -u2 -- "The configured runner port is invalid. Nothing was changed."
  exit 1
fi

process_uses_instance() {
  local process_id="$1"
  local process_cwd
  process_cwd="$(/usr/sbin/lsof -a -p "$process_id" -d cwd -Fn 2>/dev/null | /usr/bin/sed -n 's/^n//p' | /usr/bin/head -1 || true)"
  [[ -n "$process_cwd" ]] || return 1
  process_cwd="${process_cwd:A}"
  [[ "$process_cwd" == "$SOURCE_DIR" || ( -n "$RUNTIME_DIR" && "$process_cwd" == "$RUNTIME_DIR" ) ]]
}

wait_for_process_to_stop() {
  local process_id="$1"
  local attempt
  for attempt in {1..60}; do
    /bin/kill -0 "$process_id" 2>/dev/null || return 0
    /bin/sleep 0.1
  done
  return 1
}

stop_owned_listener() {
  local port="$1"
  local label="$2"
  local process_id
  process_id="$(/usr/sbin/lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | /usr/bin/head -1 || true)"
  [[ -n "$process_id" ]] || return 0

  if ! process_uses_instance "$process_id"; then
    return 0
  fi

  /bin/kill -TERM "$process_id" 2>/dev/null || true
  if ! wait_for_process_to_stop "$process_id"; then
    print -u2 -- "This folder's $label did not stop safely. Nothing was removed."
    return 1
  fi
}

stop_this_instance() {
  (( INSTANCE_IS_CONFIGURED )) || return 0
  stop_owned_listener "$RUNNER_PORT" "command runner"
  stop_owned_listener "$WEB_PORT" "dashboard"
}

if (( DRY_RUN )); then
  print -- "Control Module uninstall preview"
  [[ -n "$INSTANCE_ID" ]] && print -- "Private installation marker: verified"
  if (( REMOVE_SOURCE )); then
    print -- "Folder to move to Trash: $SOURCE_DIR"
  else
    print -- "Folder to keep: $SOURCE_DIR"
  fi
  if (( INSTANCE_IS_CONFIGURED )); then
    print -- "Local services owned by this folder: stop safely"
  else
    print -- "Local services owned by this folder: none configured"
  fi
  print -- "Other Control Module folders, apps, shortcuts, browser data, and settings: keep"
  exit 0
fi

stop_this_instance
if (( STOP_ONLY )); then
  print -- "This Control Module installation was stopped safely."
  exit 0
fi

if (( ! REMOVE_SOURCE )); then
  print -- "This Control Module folder was kept at: $SOURCE_DIR"
  exit 0
fi

TRASH_DIR="$HOME/.Trash"
/bin/mkdir -p "$TRASH_DIR"
SOURCE_TRASH_PATH="$TRASH_DIR/${SOURCE_DIR:t}"
if [[ -e "$SOURCE_TRASH_PATH" ]]; then
  SOURCE_TRASH_PATH="$TRASH_DIR/${SOURCE_DIR:t} $(/bin/date '+%Y-%m-%d %H.%M.%S')"
fi
if [[ -e "$SOURCE_TRASH_PATH" ]]; then
  SOURCE_TRASH_PATH="$SOURCE_TRASH_PATH $$"
fi

cd /
/bin/mv "$SOURCE_DIR" "$SOURCE_TRASH_PATH"
print -- "This Control Module folder was moved to Trash: $SOURCE_TRASH_PATH"
