#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
[[ -r "$SCRIPT_DIR/version.sh" ]] || { print -u2 -- "The release-version helper is missing."; exit 1; }
source "$SCRIPT_DIR/version.sh"
SOURCE_DIR="$REPOSITORY_DIR"
DESTINATION_APP="$HOME/Applications/Control Module.app"
CREATE_DESKTOP_SHORTCUT=0
LAUNCH_APP=0
WEB_PORT=1025
DESKTOP_ACCESS="private"
NODE_VERSION="24.17.0"
NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-arm64.tar.xz"
NODE_SHA256="cf7e9152d7bd86c140f6eccf3577abfbaf8960be1ca49d9d900e8484984dcb9a"
NODE_URL="https://nodejs.org/download/release/v${NODE_VERSION}/${NODE_ARCHIVE}"
CONFIG_ROOT="${CONTROL_MODULE_CONFIG_ROOT:-$HOME/Library/Application Support/Control Module}"
CONFIG_DIR=""
INSTANCE_ID=""
INSTANCE_ID_FILE=""
RUNNER_PORT=10001
RUNTIME_CACHE="$CONFIG_ROOT/runtime/node-v${NODE_VERSION}-darwin-arm64"
RUNTIME_DOWNLOAD_DIR=""
WORKSPACE_STAGING_DIR=""
SETUP_LOCK_FILE=""
SETUP_LOCK_ACQUIRED=0

cleanup() {
  if [[ -n "$RUNTIME_DOWNLOAD_DIR" && -d "$RUNTIME_DOWNLOAD_DIR" ]]; then
    /bin/rm -rf "$RUNTIME_DOWNLOAD_DIR"
  fi
  if [[ -n "$WORKSPACE_STAGING_DIR" && -d "$WORKSPACE_STAGING_DIR" ]]; then
    /bin/rm -rf "$WORKSPACE_STAGING_DIR"
  fi
  if (( SETUP_LOCK_ACQUIRED )) && [[ -n "$SETUP_LOCK_FILE" ]]; then
    /bin/rm -f "$SETUP_LOCK_FILE"
  fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

usage() {
  print -- "Usage: $0 [--source DIR] [--destination APP] [--web-port PORT] [--desktop-access private|desktop] [--desktop-shortcut] [--launch]"
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
    --desktop-access)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      DESKTOP_ACCESS="$2"
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

if [[ "$DESKTOP_ACCESS" != "private" && "$DESKTOP_ACCESS" != "desktop" ]]; then
  print -u2 -- "Desktop access must be either private or desktop."
  exit 1
fi
if [[ ! -f "$SOURCE_DIR/package.json" || ! -x "$SOURCE_DIR/ControlModule" || ! -f "$SOURCE_DIR/server/control_server.py" ]] \
  || [[ "$(/usr/bin/plutil -extract name raw "$SOURCE_DIR/package.json" 2>/dev/null || true)" != "control-module" ]]; then
  print -u2 -- "The source folder is not a verified Control Module checkout."
  exit 1
fi

case "$DESTINATION_APP" in
  "$SOURCE_DIR/Control Module.app"|"$HOME/Applications/Control Module.app") ;;
  *)
    print -u2 -- "The Control Module app can be installed only in this source folder or your personal Applications folder."
    exit 1
    ;;
esac

if [[ "$WEB_PORT" != <-> ]] || (( WEB_PORT < 1025 || WEB_PORT > 65535 )); then
  print -u2 -- "Choose a dashboard port from 1025 to 65535."
  exit 1
fi

CONFIG_ROOT="${CONFIG_ROOT:A}"
INSTANCE_ID_FILE="$SOURCE_DIR/.control-module-instance"
/bin/mkdir -p "$CONFIG_ROOT"
/bin/chmod 700 "$CONFIG_ROOT" 2>/dev/null || true
SETUP_LOCK_FILE="$CONFIG_ROOT/.setup.lock"
if ! /usr/bin/shlock -f "$SETUP_LOCK_FILE" -p $$; then
  print -u2 -- "Another Control Module Setup is already running. Let it finish, then run this Setup again."
  exit 1
fi
SETUP_LOCK_ACQUIRED=1

instance_id_is_valid() {
  print -r -- "$1" | /usr/bin/grep -Eq '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
}

new_instance_id() {
  /usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]'
}

read_project_path() {
  local settings_dir="$1"
  local saved_source=""
  [[ -r "$settings_dir/project-path" ]] || return 1
  IFS= read -r saved_source < "$settings_dir/project-path" || true
  [[ -n "$saved_source" ]] || return 1
  print -r -- "${saved_source:A}"
}

ensure_instance_id() {
  local saved_id=""
  local saved_source=""
  local temporary_file
  [[ -r "$INSTANCE_ID_FILE" ]] && IFS= read -r saved_id < "$INSTANCE_ID_FILE" || true

  if instance_id_is_valid "$saved_id"; then
    /bin/chmod 600 "$INSTANCE_ID_FILE" 2>/dev/null || true
    saved_source="$(read_project_path "$CONFIG_ROOT/instances/$saved_id" || true)"
    if [[ -z "$saved_source" || "$saved_source" == "$SOURCE_DIR" ]]; then
      print -r -- "$saved_id"
      return 0
    fi
  fi

  saved_id="$(new_instance_id)"
  instance_id_is_valid "$saved_id" || {
    print -u2 -- "A private installation marker could not be generated. Nothing was installed."
    return 1
  }
  temporary_file="$(/usr/bin/mktemp "$SOURCE_DIR/.control-module-instance.XXXXXX")"
  print -r -- "$saved_id" > "$temporary_file"
  /bin/chmod 600 "$temporary_file"
  /bin/mv -f "$temporary_file" "$INSTANCE_ID_FILE"
  print -r -- "$saved_id"
}

INSTANCE_ID="$(ensure_instance_id)"
CONFIG_DIR="$CONFIG_ROOT/instances/$INSTANCE_ID"
NEW_INSTANCE_CONFIG=0
if [[ ! -r "$CONFIG_DIR/project-path" ]]; then
  NEW_INSTANCE_CONFIG=1
fi
/bin/mkdir -p "$CONFIG_ROOT/instances" "$CONFIG_DIR"
/bin/chmod 700 "$CONFIG_ROOT" "$CONFIG_ROOT/instances" "$CONFIG_DIR" 2>/dev/null || true

reserve_instance_value() {
  local destination_file="$1"
  local value="$2"
  local temporary_file
  [[ -e "$destination_file" ]] && return 0
  temporary_file="$(/usr/bin/mktemp "$CONFIG_DIR/.instance-reservation.XXXXXX")"
  print -r -- "$value" > "$temporary_file"
  /bin/chmod 600 "$temporary_file"
  /bin/mv "$temporary_file" "$destination_file"
}

reserve_instance_value "$CONFIG_DIR/project-path" "$SOURCE_DIR"
reserve_instance_value "$CONFIG_DIR/instance-id" "$INSTANCE_ID"

LEGACY_INSTANCE=0
legacy_source="$(read_project_path "$CONFIG_ROOT" || true)"
if [[ "$legacy_source" == "$SOURCE_DIR" ]]; then
  LEGACY_INSTANCE=1
fi

CURRENT_WEB_PORT=1025
if [[ -r "$CONFIG_DIR/web-port" ]]; then
  IFS= read -r CURRENT_WEB_PORT < "$CONFIG_DIR/web-port" || true
elif (( LEGACY_INSTANCE )) && [[ -r "$CONFIG_ROOT/web-port" ]]; then
  IFS= read -r CURRENT_WEB_PORT < "$CONFIG_ROOT/web-port" || true
fi
if [[ "$CURRENT_WEB_PORT" != <-> ]] || (( CURRENT_WEB_PORT < 1025 || CURRENT_WEB_PORT > 65535 )); then
  CURRENT_WEB_PORT=1025
fi

CURRENT_RUNNER_PORT=10001
if [[ -r "$CONFIG_DIR/runner-port" ]]; then
  IFS= read -r CURRENT_RUNNER_PORT < "$CONFIG_DIR/runner-port" || true
fi
if [[ "$CURRENT_RUNNER_PORT" != <-> ]] || (( CURRENT_RUNNER_PORT < 1025 || CURRENT_RUNNER_PORT > 65535 )); then
  CURRENT_RUNNER_PORT=10001
fi

CURRENT_DESKTOP_ACCESS="desktop"
if [[ -r "$CONFIG_DIR/desktop-access" ]]; then
  IFS= read -r CURRENT_DESKTOP_ACCESS < "$CONFIG_DIR/desktop-access" || true
fi
if [[ "$CURRENT_DESKTOP_ACCESS" != "private" && "$CURRENT_DESKTOP_ACCESS" != "desktop" ]]; then
  CURRENT_DESKTOP_ACCESS="desktop"
fi

CURRENT_RUNTIME_DIR="$SOURCE_DIR"
if [[ -r "$CONFIG_DIR/runtime-path" ]]; then
  IFS= read -r CURRENT_RUNTIME_DIR < "$CONFIG_DIR/runtime-path" || true
fi
[[ -n "$CURRENT_RUNTIME_DIR" ]] || CURRENT_RUNTIME_DIR="$SOURCE_DIR"
CURRENT_RUNTIME_DIR="${CURRENT_RUNTIME_DIR:A}"
if [[ "$CURRENT_RUNTIME_DIR" != "$SOURCE_DIR" && "$CURRENT_RUNTIME_DIR" != "$CONFIG_DIR/workspace" ]]; then
  CURRENT_RUNTIME_DIR=""
fi

CURRENT_INSTALL_APP=""
if [[ -r "$CONFIG_DIR/install-path" ]]; then
  IFS= read -r CURRENT_INSTALL_APP < "$CONFIG_DIR/install-path" || true
fi
[[ -n "$CURRENT_INSTALL_APP" ]] && CURRENT_INSTALL_APP="${CURRENT_INSTALL_APP:A}"

app_instance_id() {
  local app_path="$1"
  local app_id=""
  [[ -r "$app_path/Contents/Resources/instance-id" ]] || return 1
  IFS= read -r app_id < "$app_path/Contents/Resources/instance-id" || true
  instance_id_is_valid "$app_id" || return 1
  print -r -- "$app_id"
}

SOURCE_VERSION="$(control_module_version_label "$SOURCE_DIR" || true)"
INSTALLED_VERSION=""
HAS_VERIFIED_INSTALLATION=0
VERSION_RELATION="unknown"
if [[ -n "$CURRENT_INSTALL_APP" && -d "$CURRENT_INSTALL_APP" && ! -L "$CURRENT_INSTALL_APP" \
  && "$(app_instance_id "$CURRENT_INSTALL_APP" || true)" == "$INSTANCE_ID" ]]; then
  HAS_VERIFIED_INSTALLATION=1
  INSTALLED_VERSION="$(control_module_version_label "$CURRENT_RUNTIME_DIR" 2>/dev/null || true)"
fi
if (( HAS_VERIFIED_INSTALLATION )); then
  if [[ -z "$SOURCE_VERSION" || -z "$INSTALLED_VERSION" ]]; then
    print -u2 -- "Setup could not verify the downloaded and installed release versions. The installed app was not replaced."
    exit 1
  fi
  VERSION_RELATION="$(control_module_version_relation "$SOURCE_VERSION" "$INSTALLED_VERSION")"
  if [[ "$VERSION_RELATION" == "unknown" ]]; then
    print -u2 -- "Setup could not safely compare the downloaded and installed release versions. The installed app was not replaced."
    exit 1
  fi
  if [[ "$VERSION_RELATION" == "older" ]]; then
    print -u2 -- "This download is $SOURCE_VERSION, but this copy already has $INSTALLED_VERSION. Setup blocks downgrades so an older download cannot replace a newer installation. Download the latest release instead."
    exit 1
  fi
fi

if [[ "$DESKTOP_ACCESS" == "private" ]]; then
  DESIRED_RUNTIME_DIR="$CONFIG_DIR/workspace"
else
  DESIRED_RUNTIME_DIR="$SOURCE_DIR"
fi

listener_uses_instance() {
  local port="$1"
  local process_id process_cwd
  process_id="$(/usr/sbin/lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | /usr/bin/head -1 || true)"
  [[ -n "$process_id" ]] || return 1
  process_cwd="$(/usr/sbin/lsof -a -p "$process_id" -d cwd -Fn 2>/dev/null | /usr/bin/sed -n 's/^n//p' | /usr/bin/head -1 || true)"
  [[ -n "$process_cwd" ]] || return 1
  process_cwd="${process_cwd:A}"
  [[ "$process_cwd" == "$SOURCE_DIR" || "$process_cwd" == "$CURRENT_RUNTIME_DIR" ]]
}

runner_port_is_reserved_by_other_instance() {
  local candidate="$1"
  local port_file reserved_port owner_source
  for port_file in "$CONFIG_ROOT/instances/"*/runner-port(N); do
    [[ "${port_file:h}" == "$CONFIG_DIR" ]] && continue
    reserved_port=""
    IFS= read -r reserved_port < "$port_file" || true
    [[ "$reserved_port" == "$candidate" ]] || continue
    owner_source="$(read_project_path "${port_file:h}" || true)"
    if [[ -n "$owner_source" && -d "$owner_source" && "$owner_source" != "$SOURCE_DIR" ]]; then
      return 0
    fi
  done
  return 1
}

web_port_is_reserved_by_other_instance() {
  local candidate="$1"
  local port_file reserved_port owner_source
  for port_file in "$CONFIG_ROOT/instances/"*/web-port(N); do
    [[ "${port_file:h}" == "$CONFIG_DIR" ]] && continue
    reserved_port=""
    IFS= read -r reserved_port < "$port_file" || true
    [[ "$reserved_port" == "$candidate" ]] || continue
    owner_source="$(read_project_path "${port_file:h}" || true)"
    if [[ -n "$owner_source" && -d "$owner_source" && "$owner_source" != "$SOURCE_DIR" ]]; then
      return 0
    fi
  done
  return 1
}

runner_port_can_be_used() {
  local candidate="$1"
  (( candidate != WEB_PORT )) || return 1
  runner_port_is_reserved_by_other_instance "$candidate" && return 1
  if /usr/sbin/lsof -nP -iTCP:"$candidate" -sTCP:LISTEN >/dev/null 2>&1; then
    listener_uses_instance "$candidate"
    return $?
  fi
  return 0
}

if runner_port_can_be_used "$CURRENT_RUNNER_PORT"; then
  RUNNER_PORT="$CURRENT_RUNNER_PORT"
else
  RUNNER_PORT=""
  for candidate in {10001..10999}; do
    if runner_port_can_be_used "$candidate"; then
      RUNNER_PORT="$candidate"
      break
    fi
  done
  if [[ -z "$RUNNER_PORT" ]]; then
    print -u2 -- "No private runner port is available from 10001 to 10999. Stop another local service and run Setup again."
    exit 1
  fi
fi

NEEDS_LEGACY_MIGRATION=0
if (( LEGACY_INSTANCE && NEW_INSTANCE_CONFIG )); then
  NEEDS_LEGACY_MIGRATION=1
  reserve_instance_value "$CONFIG_DIR/web-port" "$CURRENT_WEB_PORT"
  reserve_instance_value "$CONFIG_DIR/runner-port" "$CURRENT_RUNNER_PORT"
fi

if web_port_is_reserved_by_other_instance "$WEB_PORT"; then
  print -u2 -- "Port $WEB_PORT is reserved by another Control Module installation. Choose another dashboard port."
  exit 1
fi

if /usr/sbin/lsof -nP -iTCP:"$WEB_PORT" -sTCP:LISTEN >/dev/null 2>&1 \
  && ! listener_uses_instance "$WEB_PORT"; then
  print -u2 -- "Port $WEB_PORT is already being used by another program or Control Module installation. Choose another dashboard port."
  exit 1
fi

if { (( NEEDS_LEGACY_MIGRATION )) || [[ "$CURRENT_WEB_PORT" != "$WEB_PORT" ]]; } \
  && { listener_uses_instance "$CURRENT_WEB_PORT" || listener_uses_instance "$CURRENT_RUNNER_PORT"; }; then
  CONTROL_MODULE_CONFIG_ROOT="$CONFIG_ROOT" "$SCRIPT_DIR/uninstall.sh" --source "$SOURCE_DIR" --stop-only >/dev/null
fi

# A private workspace is replaced atomically on every Setup run. Stop this
# installation first so no process keeps serving files from the retired copy.
if [[ "$DESKTOP_ACCESS" == "private" ]] \
  && { listener_uses_instance "$CURRENT_WEB_PORT" || listener_uses_instance "$CURRENT_RUNNER_PORT"; }; then
  CONTROL_MODULE_CONFIG_ROOT="$CONFIG_ROOT" "$SCRIPT_DIR/uninstall.sh" --source "$SOURCE_DIR" --stop-only >/dev/null
fi

if [[ "$CURRENT_DESKTOP_ACCESS" != "$DESKTOP_ACCESS" || "$CURRENT_RUNTIME_DIR" != "$DESIRED_RUNTIME_DIR" ]] \
  && { listener_uses_instance "$CURRENT_WEB_PORT" || listener_uses_instance "$CURRENT_RUNNER_PORT"; }; then
  CONTROL_MODULE_CONFIG_ROOT="$CONFIG_ROOT" "$SCRIPT_DIR/uninstall.sh" --source "$SOURCE_DIR" --stop-only >/dev/null
fi

if [[ -n "$CURRENT_INSTALL_APP" && "$CURRENT_INSTALL_APP" != "$DESTINATION_APP" ]] \
  && { listener_uses_instance "$CURRENT_WEB_PORT" || listener_uses_instance "$CURRENT_RUNNER_PORT"; }; then
  CONTROL_MODULE_CONFIG_ROOT="$CONFIG_ROOT" "$SCRIPT_DIR/uninstall.sh" --source "$SOURCE_DIR" --stop-only >/dev/null
fi

if [[ -e "$DESTINATION_APP" && "${DESTINATION_APP:h}" != "$SOURCE_DIR" ]]; then
  destination_id="$(app_instance_id "$DESTINATION_APP" || true)"
  if [[ "$destination_id" != "$INSTANCE_ID" ]]; then
    if [[ -n "$destination_id" ]] || (( ! LEGACY_INSTANCE )); then
      DESTINATION_APP="${DESTINATION_APP:h}/Control Module ${INSTANCE_ID[1,8]}.app"
    fi
  fi
fi

if (( CREATE_DESKTOP_SHORTCUT )); then
  DESKTOP_SHORTCUT="$HOME/Desktop/Control Module.app"
  if [[ "$DESKTOP_SHORTCUT" != "$DESTINATION_APP" && ( -e "$DESKTOP_SHORTCUT" || -L "$DESKTOP_SHORTCUT" ) ]]; then
    shortcut_target=""
    shortcut_id=""
    [[ -L "$DESKTOP_SHORTCUT" ]] && shortcut_target="${DESKTOP_SHORTCUT:A}" || true
    [[ -n "$shortcut_target" ]] && shortcut_id="$(app_instance_id "$shortcut_target" || true)"
    if [[ "$shortcut_target" != "$DESTINATION_APP" && "$shortcut_id" != "$INSTANCE_ID" ]]; then
      DESKTOP_SHORTCUT="$HOME/Desktop/Control Module ${INSTANCE_ID[1,8]}.app"
    fi
  fi
  if [[ "$DESKTOP_SHORTCUT" != "$DESTINATION_APP" && ! -L "$DESKTOP_SHORTCUT" && -e "$DESKTOP_SHORTCUT" ]]; then
    print -u2 -- "A Desktop item already uses this installation's Control Module name. It was left unchanged."
    exit 1
  fi
fi

runtime_is_valid() {
  local runtime_dir="$1"
  [[ -x "$runtime_dir/bin/node" && -x "$runtime_dir/bin/corepack" && -f "$runtime_dir/LICENSE" ]] || return 1
  [[ "$(/usr/bin/lipo -archs "$runtime_dir/bin/node" 2>/dev/null || true)" == "arm64" ]] || return 1
  [[ "$("$runtime_dir/bin/node" --version 2>/dev/null || true)" == "v$NODE_VERSION" ]]
}

prune_runtime() {
  local runtime_dir="$1"
  /bin/rm -rf \
    "$runtime_dir/include" \
    "$runtime_dir/share" \
    "$runtime_dir/CHANGELOG.md" \
    "$runtime_dir/README.md"
}

ensure_runtime() {
  local archive_path extracted_runtime previous_runtime actual_checksum

  if runtime_is_valid "$RUNTIME_CACHE"; then
    prune_runtime "$RUNTIME_CACHE"
    return 0
  fi

  /bin/mkdir -p "$CONFIG_ROOT/runtime"
  /bin/chmod 700 "$CONFIG_ROOT" "$CONFIG_ROOT/runtime"
  RUNTIME_DOWNLOAD_DIR="$(/usr/bin/mktemp -d "$CONFIG_ROOT/runtime/.node-download.XXXXXX")"
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
  prune_runtime "$extracted_runtime"

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

migrate_legacy_instance() {
  local setting
  (( LEGACY_INSTANCE && NEW_INSTANCE_CONFIG )) || return 0
  /bin/mkdir -p "$CONFIG_ROOT/instances" "$CONFIG_DIR"
  /bin/chmod 700 "$CONFIG_ROOT" "$CONFIG_ROOT/instances" "$CONFIG_DIR" 2>/dev/null || true
  for setting in project-path install-path web-port desktop-access runtime-path; do
    if [[ -f "$CONFIG_ROOT/$setting" && ! -e "$CONFIG_DIR/$setting" ]]; then
      /bin/cp "$CONFIG_ROOT/$setting" "$CONFIG_DIR/$setting"
      /bin/chmod 600 "$CONFIG_DIR/$setting"
    fi
  done
  if [[ -d "$CONFIG_ROOT/data" && ! -e "$CONFIG_DIR/data" ]]; then
    /usr/bin/ditto "$CONFIG_ROOT/data" "$CONFIG_DIR/data"
    /bin/chmod -R go-rwx "$CONFIG_DIR/data"
  fi
}

prepare_private_workspace() {
  local workspace_parent previous_workspace source_item
  typeset -a source_items
  [[ "$DESKTOP_ACCESS" == "private" ]] || return 0

  workspace_parent="${DESIRED_RUNTIME_DIR:h}"
  /bin/mkdir -p "$workspace_parent"
  /bin/chmod 700 "$workspace_parent"
  WORKSPACE_STAGING_DIR="$(/usr/bin/mktemp -d "$workspace_parent/.workspace-install.XXXXXX")"

  source_items=(
    app
    lib
    public
    server
    package.json
    pnpm-lock.yaml
    pnpm-workspace.yaml
    proxy.ts
    next.config.ts
    tsconfig.json
    vite.config.ts
    version.json
  )
  for source_item in "${source_items[@]}"; do
    [[ -e "$SOURCE_DIR/$source_item" ]] || continue
    /usr/bin/ditto "$SOURCE_DIR/$source_item" "$WORKSPACE_STAGING_DIR/$source_item"
  done

  # Standalone output contains only the packages required to serve the built dashboard.
  if [[ -f "$SOURCE_DIR/dist/standalone/server.js" ]]; then
    /usr/bin/ditto "$SOURCE_DIR/dist/standalone" "$WORKSPACE_STAGING_DIR/dist/standalone"
  fi

  print -r -- "$INSTANCE_ID" > "$WORKSPACE_STAGING_DIR/.instance-id"
  /bin/chmod -R go-rwx "$WORKSPACE_STAGING_DIR"

  previous_workspace="$workspace_parent/.workspace-previous.$$"
  if [[ -e "$DESIRED_RUNTIME_DIR" ]]; then
    /bin/mv "$DESIRED_RUNTIME_DIR" "$previous_workspace"
  fi
  if ! /bin/mv "$WORKSPACE_STAGING_DIR" "$DESIRED_RUNTIME_DIR"; then
    [[ -e "$previous_workspace" ]] && /bin/mv "$previous_workspace" "$DESIRED_RUNTIME_DIR"
    print -u2 -- "The private Control Module working copy could not be installed."
    return 1
  fi
  WORKSPACE_STAGING_DIR=""
  [[ -e "$previous_workspace" ]] && /bin/rm -rf "$previous_workspace"
}

migrate_legacy_instance
ensure_runtime
prepare_private_workspace
"$SCRIPT_DIR/app.sh" --source "$SOURCE_DIR" --output "$DESTINATION_APP" --runtime "$RUNTIME_CACHE" --instance-id "$INSTANCE_ID" >/dev/null

PROJECT_PATH_FILE="$CONFIG_DIR/project-path"
INSTALL_PATH_FILE="$CONFIG_DIR/install-path"
WEB_PORT_FILE="$CONFIG_DIR/web-port"
RUNNER_PORT_FILE="$CONFIG_DIR/runner-port"
CONFIG_INSTANCE_ID_FILE="$CONFIG_DIR/instance-id"
SHORTCUT_PATH_FILE="$CONFIG_DIR/shortcut-path"
RUNTIME_PATH_FILE="$CONFIG_DIR/runtime-path"
DESKTOP_ACCESS_FILE="$CONFIG_DIR/desktop-access"
/bin/mkdir -p "$CONFIG_ROOT/instances" "$CONFIG_DIR"
/bin/chmod 700 "$CONFIG_ROOT" "$CONFIG_ROOT/instances" "$CONFIG_DIR"

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
write_private_path "$RUNNER_PORT_FILE" "$RUNNER_PORT"
write_private_path "$CONFIG_INSTANCE_ID_FILE" "$INSTANCE_ID"
write_private_path "$RUNTIME_PATH_FILE" "$DESIRED_RUNTIME_DIR"
write_private_path "$DESKTOP_ACCESS_FILE" "$DESKTOP_ACCESS"

if (( CREATE_DESKTOP_SHORTCUT )); then
  if [[ "$DESKTOP_SHORTCUT" != "$DESTINATION_APP" ]]; then
    if [[ -L "$DESKTOP_SHORTCUT" ]]; then
      /bin/rm "$DESKTOP_SHORTCUT"
    fi
    /bin/ln -s "$DESTINATION_APP" "$DESKTOP_SHORTCUT"
  fi
  write_private_path "$SHORTCUT_PATH_FILE" "$DESKTOP_SHORTCUT"
elif [[ -r "$SHORTCUT_PATH_FILE" ]]; then
  previous_shortcut=""
  previous_shortcut_target=""
  previous_shortcut_id=""
  IFS= read -r previous_shortcut < "$SHORTCUT_PATH_FILE" || true
  if [[ -n "$previous_shortcut" && -L "$previous_shortcut" ]]; then
    previous_shortcut_target="${previous_shortcut:A}"
    previous_shortcut_id="$(app_instance_id "$previous_shortcut_target" || true)"
    if [[ "$previous_shortcut_id" == "$INSTANCE_ID" ]]; then
      /bin/rm "$previous_shortcut"
    fi
  fi
  /bin/rm -f "$SHORTCUT_PATH_FILE"
fi

retire_previous_app() {
  local trash_dir trash_path
  [[ -n "$CURRENT_INSTALL_APP" && "$CURRENT_INSTALL_APP" != "$DESTINATION_APP" ]] || return 0
  [[ -d "$CURRENT_INSTALL_APP" && ! -L "$CURRENT_INSTALL_APP" ]] || return 0
  [[ "$(app_instance_id "$CURRENT_INSTALL_APP" || true)" == "$INSTANCE_ID" ]] || return 0
  case "$CURRENT_INSTALL_APP" in
    "$SOURCE_DIR"/Control\ Module*.app|"$HOME/Applications"/Control\ Module*.app) ;;
    *) return 0 ;;
  esac
  trash_dir="$HOME/.Trash"
  /bin/mkdir -p "$trash_dir"
  trash_path="$trash_dir/${CURRENT_INSTALL_APP:t}"
  if [[ -e "$trash_path" ]]; then
    trash_path="$trash_dir/${CURRENT_INSTALL_APP:t:r} $(/bin/date '+%Y-%m-%d %H.%M.%S').app"
  fi
  [[ -e "$trash_path" ]] && trash_path="$trash_dir/${CURRENT_INSTALL_APP:t:r} $$.app"
  /bin/mv "$CURRENT_INSTALL_APP" "$trash_path"
}

retire_previous_app

if (( LAUNCH_APP )); then
  CONTROL_MODULE_CONFIG_ROOT="$CONFIG_ROOT" "$SCRIPT_DIR/manage.sh" start --source "$SOURCE_DIR" >/dev/null
fi

print -- "Control Module was installed at $DESTINATION_APP"
