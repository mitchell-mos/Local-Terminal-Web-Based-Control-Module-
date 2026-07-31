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
NODE_VERSION="24.17.0"
NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-arm64.tar.xz"
NODE_SHA256="cf7e9152d7bd86c140f6eccf3577abfbaf8960be1ca49d9d900e8484984dcb9a"
NODE_URL="https://nodejs.org/download/release/v${NODE_VERSION}/${NODE_ARCHIVE}"
CONFIG_DIR="${CONTROL_MODULE_CONFIG_DIR:-$HOME/Library/Application Support/Control Module}"
RUNTIME_CACHE="$CONFIG_DIR/runtime/node-v${NODE_VERSION}-darwin-arm64"
RUNTIME_DOWNLOAD_DIR=""

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

if [[ "$(/usr/bin/uname -m)" != "arm64" ]]; then
  print -u2 -- "Control Module requires an Apple silicon Mac. Intel Macs and Rosetta translation are not supported."
  exit 1
fi

SOURCE_DIR="${SOURCE_DIR:A}"
DESTINATION_APP="${DESTINATION_APP:A}"

if [[ ! -f "$SOURCE_DIR/package.json" || ! -x "$SOURCE_DIR/ControlModule" || ! -f "$SOURCE_DIR/server/control_server.py" ]]; then
  print -u2 -- "The source folder is not a verified Control Module checkout."
  exit 1
fi

if [[ "$WEB_PORT" != <-> ]] || (( WEB_PORT < 1025 || WEB_PORT > 65535 || WEB_PORT == 10001 )); then
  print -u2 -- "Choose a dashboard port from 1025 to 65535, excluding the reserved runner port 10001."
  exit 1
fi

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

runtime_is_valid() {
  local runtime_dir="$1"
  [[ -x "$runtime_dir/bin/node" && -x "$runtime_dir/bin/corepack" && -f "$runtime_dir/LICENSE" ]] || return 1
  [[ "$(/usr/bin/lipo -archs "$runtime_dir/bin/node" 2>/dev/null || true)" == "arm64" ]] || return 1
  [[ "$("$runtime_dir/bin/node" --version 2>/dev/null || true)" == "v$NODE_VERSION" ]]
}

cleanup_runtime_download() {
  if [[ -n "$RUNTIME_DOWNLOAD_DIR" && -d "$RUNTIME_DOWNLOAD_DIR" ]]; then
    /bin/rm -rf "$RUNTIME_DOWNLOAD_DIR"
  fi
}
trap cleanup_runtime_download EXIT HUP INT TERM

ensure_runtime() {
  local archive_path extracted_runtime previous_runtime actual_checksum

  if runtime_is_valid "$RUNTIME_CACHE"; then
    return 0
  fi

  /bin/mkdir -p "$CONFIG_DIR/runtime"
  /bin/chmod 700 "$CONFIG_DIR" "$CONFIG_DIR/runtime"
  RUNTIME_DOWNLOAD_DIR="$(/usr/bin/mktemp -d "$CONFIG_DIR/runtime/.node-download.XXXXXX")"
  archive_path="$RUNTIME_DOWNLOAD_DIR/$NODE_ARCHIVE"
  print -u2 -- "Downloading the official Node.js $NODE_VERSION ARM64 runtime…"
  if ! /usr/bin/curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --output "$archive_path" "$NODE_URL"; then
    print -u2 -- "The official Node.js ARM64 runtime could not be downloaded. Check your internet connection and run Setup again."
    return 1
  fi

  actual_checksum="$(/usr/bin/shasum -a 256 "$archive_path" | /usr/bin/awk '{print $1}')"
  if [[ "$actual_checksum" != "$NODE_SHA256" ]]; then
    print -u2 -- "The Node.js runtime checksum did not match the trusted release. Nothing was installed."
    return 1
  fi

  /usr/bin/tar -xJf "$archive_path" -C "$RUNTIME_DOWNLOAD_DIR"
  extracted_runtime="$RUNTIME_DOWNLOAD_DIR/node-v${NODE_VERSION}-darwin-arm64"
  if ! runtime_is_valid "$extracted_runtime"; then
    print -u2 -- "The downloaded Node.js runtime is incomplete or is not ARM64. Nothing was installed."
    return 1
  fi

  previous_runtime="$RUNTIME_DOWNLOAD_DIR/previous-runtime"
  if [[ -e "$RUNTIME_CACHE" ]]; then
    /bin/mv "$RUNTIME_CACHE" "$previous_runtime"
  fi
  if ! /bin/mv "$extracted_runtime" "$RUNTIME_CACHE"; then
    [[ -e "$previous_runtime" ]] && /bin/mv "$previous_runtime" "$RUNTIME_CACHE"
    print -u2 -- "The verified Node.js runtime could not be stored. Nothing was installed."
    return 1
  fi
  /bin/chmod -R go-rwx "$RUNTIME_CACHE"
}

ensure_runtime
"$SCRIPT_DIR/app.sh" --source "$SOURCE_DIR" --output "$DESTINATION_APP" --runtime "$RUNTIME_CACHE" >/dev/null

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
