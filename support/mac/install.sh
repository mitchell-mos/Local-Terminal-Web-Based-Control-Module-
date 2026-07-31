#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
SOURCE_DIR="$REPOSITORY_DIR"
DESTINATION_APP="$HOME/Applications/Control Module.app"
CREATE_DESKTOP_SHORTCUT=0
LAUNCH_APP=0
WEB_PORT=1025

usage() {
  print -- "Usage: $0 [--source DIR] [--destination APP] [--web-port PORT] [--desktop-shortcut] [--launch]"
}

while (( $# > 0 )); do
  case "$1" in
    --source)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      SOURCE_DIR="$2"
      shift 2
      ;;
    --destination)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      DESTINATION_APP="$2"
      shift 2
      ;;
    --web-port)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      WEB_PORT="$2"
      shift 2
      ;;
    --desktop-shortcut)
      CREATE_DESKTOP_SHORTCUT=1
      shift
      ;;
    --launch)
      LAUNCH_APP=1
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

SOURCE_DIR="${SOURCE_DIR:A}"
DESTINATION_APP="${DESTINATION_APP:A}"

if [[ ! -f "$SOURCE_DIR/package.json" || ! -x "$SOURCE_DIR/ControlModule" || ! -f "$SOURCE_DIR/server/control_server.py" ]]; then
  print -u2 -- "The selected source folder is not a Control Module checkout."
  exit 1
fi

if [[ "$WEB_PORT" != <-> ]] || (( WEB_PORT < 1025 || WEB_PORT > 65535 || WEB_PORT == 10001 )); then
  print -u2 -- "Choose a dashboard port from 1025 to 65535, excluding the reserved runner port 10001."
  exit 1
fi

CONFIG_DIR="${CONTROL_MODULE_CONFIG_DIR:-$HOME/Library/Application Support/Control Module}"
CURRENT_WEB_PORT=1025
if [[ -r "$CONFIG_DIR/web-port" ]]; then
  IFS= read -r CURRENT_WEB_PORT < "$CONFIG_DIR/web-port" || true
fi
if [[ "$CURRENT_WEB_PORT" != <-> ]] || (( CURRENT_WEB_PORT < 1025 || CURRENT_WEB_PORT > 65535 || CURRENT_WEB_PORT == 10001 )); then
  CURRENT_WEB_PORT=1025
fi

if [[ "$CURRENT_WEB_PORT" != "$WEB_PORT" ]] \
  && { /usr/sbin/lsof -nP -iTCP:"$CURRENT_WEB_PORT" -sTCP:LISTEN >/dev/null 2>&1 \
    || /usr/sbin/lsof -nP -iTCP:10001 -sTCP:LISTEN >/dev/null 2>&1; }; then
  "$SCRIPT_DIR/uninstall.sh" --source "$SOURCE_DIR" --stop-only >/dev/null
fi

if /usr/sbin/lsof -nP -iTCP:"$WEB_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  if ! /usr/bin/curl -fsS "http://127.0.0.1:$WEB_PORT/" 2>/dev/null | /usr/bin/grep -q "Control Module"; then
    print -u2 -- "Port $WEB_PORT is already being used by another program. Choose another dashboard port."
    exit 1
  fi
fi

if (( CREATE_DESKTOP_SHORTCUT )); then
  DESKTOP_SHORTCUT="$HOME/Desktop/Control Module.app"
  if [[ "$DESKTOP_SHORTCUT" != "$DESTINATION_APP" && ! -L "$DESKTOP_SHORTCUT" && -e "$DESKTOP_SHORTCUT" ]]; then
    print -u2 -- "A file named Control Module.app already exists on the Desktop. It was left unchanged."
    exit 1
  fi
fi

"$SCRIPT_DIR/app.sh" --source "$SOURCE_DIR" --output "$DESTINATION_APP" >/dev/null

PROJECT_PATH_FILE="$CONFIG_DIR/project-path"
INSTALL_PATH_FILE="$CONFIG_DIR/install-path"
WEB_PORT_FILE="$CONFIG_DIR/web-port"
/bin/mkdir -p "$CONFIG_DIR"
/bin/chmod 700 "$CONFIG_DIR"

write_private_path() {
  local destination_file="$1"
  local path_value="$2"
  local temporary_file
  temporary_file="$(/usr/bin/mktemp "$CONFIG_DIR/.install-setting.XXXXXX")"
  print -r -- "$path_value" > "$temporary_file"
  /bin/chmod 600 "$temporary_file"
  /bin/mv -f "$temporary_file" "$destination_file"
}

write_private_path "$PROJECT_PATH_FILE" "$SOURCE_DIR"
write_private_path "$INSTALL_PATH_FILE" "$DESTINATION_APP"
write_private_path "$WEB_PORT_FILE" "$WEB_PORT"

if (( CREATE_DESKTOP_SHORTCUT )); then
  if [[ "$DESKTOP_SHORTCUT" != "$DESTINATION_APP" ]]; then
    if [[ -L "$DESKTOP_SHORTCUT" ]]; then
      /bin/rm "$DESKTOP_SHORTCUT"
    fi
    /bin/ln -s "$DESTINATION_APP" "$DESKTOP_SHORTCUT"
  fi
fi

if (( LAUNCH_APP )); then
  /usr/bin/open "$DESTINATION_APP"
fi

print -- "Control Module was installed at $DESTINATION_APP"
