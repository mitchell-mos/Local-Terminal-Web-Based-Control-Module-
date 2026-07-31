#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
SOURCE_DIR="$REPOSITORY_DIR"
OUTPUT_APP="$REPOSITORY_DIR/release/Control Module.app"
RUNTIME_DIR=""
SIGN_APP=1

usage() {
  print -- "Usage: $0 [--source DIR] [--output APP] [--runtime DIR] [--no-sign]"
}

while (( $# > 0 )); do
  case "$1" in
    --source)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      SOURCE_DIR="$2"
      shift 2
      ;;
    --output)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      OUTPUT_APP="$2"
      shift 2
      ;;
    --runtime)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      RUNTIME_DIR="$2"
      shift 2
      ;;
    --no-sign)
      SIGN_APP=0
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
OUTPUT_APP="${OUTPUT_APP:A}"

if [[ ! -f "$SOURCE_DIR/package.json" || ! -x "$SOURCE_DIR/ControlModule" || ! -f "$SOURCE_DIR/server/control_server.py" ]]; then
  print -u2 -- "The source folder must contain package.json, ControlModule, and server/control_server.py."
  exit 1
fi

if [[ "${OUTPUT_APP:t}" != "Control Module.app" ]]; then
  print -u2 -- "The output must be an app named Control Module.app."
  exit 1
fi

if [[ -z "$RUNTIME_DIR" && -x "$OUTPUT_APP/Contents/Resources/runtime/bin/node" ]]; then
  RUNTIME_DIR="$OUTPUT_APP/Contents/Resources/runtime"
fi

if [[ -n "$RUNTIME_DIR" ]]; then
  RUNTIME_DIR="${RUNTIME_DIR:A}"
  if [[ ! -x "$RUNTIME_DIR/bin/node" ]]; then
    print -u2 -- "The runtime folder must contain an executable bin/node file."
    exit 1
  fi
fi

OUTPUT_PARENT="${OUTPUT_APP:h}"
/bin/mkdir -p "$OUTPUT_PARENT"
STAGING_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/control-module-app.XXXXXX")"
STAGING_APP="$STAGING_ROOT/Control Module.app"

cleanup() {
  /bin/rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT HUP INT TERM

/bin/mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"
/bin/cp "$SOURCE_DIR/ControlModule" "$STAGING_APP/Contents/MacOS/ControlModule"
/bin/chmod 755 "$STAGING_APP/Contents/MacOS/ControlModule"
/bin/cp "$SOURCE_DIR/support/mac/App.plist" "$STAGING_APP/Contents/Info.plist"
/bin/cp "$SOURCE_DIR/support/mac/App.icns" "$STAGING_APP/Contents/Resources/ControlModule.icns"

if [[ -n "$RUNTIME_DIR" ]]; then
  /bin/mkdir -p "$STAGING_APP/Contents/Resources/runtime/bin"
  /bin/cp "$RUNTIME_DIR/bin/node" "$STAGING_APP/Contents/Resources/runtime/bin/node"
  /bin/chmod 755 "$STAGING_APP/Contents/Resources/runtime/bin/node"
  if [[ -f "$RUNTIME_DIR/LICENSE-node.txt" ]]; then
    /bin/cp "$RUNTIME_DIR/LICENSE-node.txt" "$STAGING_APP/Contents/Resources/runtime/LICENSE-node.txt"
  elif [[ -f "$RUNTIME_DIR/LICENSE" ]]; then
    /bin/cp "$RUNTIME_DIR/LICENSE" "$STAGING_APP/Contents/Resources/runtime/LICENSE-node.txt"
  fi
fi

BACKUP_APP=""
if [[ -e "$OUTPUT_APP" || -L "$OUTPUT_APP" ]]; then
  BACKUP_APP="$STAGING_ROOT/previous-Control Module.app"
  /bin/mv "$OUTPUT_APP" "$BACKUP_APP"
fi

if ! /bin/mv "$STAGING_APP" "$OUTPUT_APP"; then
  if [[ -n "$BACKUP_APP" && -e "$BACKUP_APP" ]]; then
    /bin/mv "$BACKUP_APP" "$OUTPUT_APP"
  fi
  exit 1
fi

/usr/bin/touch "$OUTPUT_APP"
if [[ -x /usr/bin/xattr ]]; then
  /usr/bin/xattr -cr "$OUTPUT_APP"
fi
if (( SIGN_APP )) && [[ -x /usr/bin/codesign ]]; then
  /usr/bin/codesign --force --deep --sign - "$OUTPUT_APP" >/dev/null
  /bin/sleep 0.5
  /usr/bin/xattr -d com.apple.FinderInfo "$OUTPUT_APP" 2>/dev/null || true
  /usr/bin/codesign --verify --deep "$OUTPUT_APP"
fi
print -- "$OUTPUT_APP"
