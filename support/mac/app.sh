#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
SOURCE_DIR="$REPOSITORY_DIR"
OUTPUT_APP="$REPOSITORY_DIR/release/Control Module.app"
RUNTIME_DIR=""
SIGN_APP=1
SOURCE_LAUNCHER="$SCRIPT_DIR/Launch.applescript"

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

if [[ ! -f "$SOURCE_DIR/package.json" || ! -x "$SOURCE_DIR/ControlModule" || ! -f "$SOURCE_DIR/server/control_server.py" || ! -f "$SOURCE_LAUNCHER" ]]; then
  print -u2 -- "The source folder must contain the Control Module launcher, package, server, and native launcher source."
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

/usr/bin/osacompile -o "$STAGING_APP" "$SOURCE_LAUNCHER"
/bin/cp "$SOURCE_DIR/ControlModule" "$STAGING_APP/Contents/Resources/ControlModule"
/bin/chmod 755 "$STAGING_APP/Contents/Resources/ControlModule"
/bin/cp "$SOURCE_DIR/support/mac/App.plist" "$STAGING_APP/Contents/Info.plist"
/bin/cp "$SOURCE_DIR/support/mac/App.icns" "$STAGING_APP/Contents/Resources/ControlModule.icns"

APPLET_EXECUTABLE="$STAGING_APP/Contents/MacOS/applet"
ARM_APPLET="$STAGING_ROOT/applet-arm64"
if ! /usr/bin/lipo "$APPLET_EXECUTABLE" -verify_arch arm64 >/dev/null 2>&1; then
  print -u2 -- "The native launcher does not contain an Apple silicon arm64 executable."
  exit 1
fi
/usr/bin/lipo "$APPLET_EXECUTABLE" -thin arm64 -output "$ARM_APPLET"
/bin/chmod 755 "$ARM_APPLET"
/bin/mv "$ARM_APPLET" "$APPLET_EXECUTABLE"

if [[ -n "$RUNTIME_DIR" ]]; then
  /usr/bin/ditto "$RUNTIME_DIR" "$STAGING_APP/Contents/Resources/runtime"
  /bin/chmod 755 "$STAGING_APP/Contents/Resources/runtime/bin/node"
  [[ -e "$STAGING_APP/Contents/Resources/runtime/bin/corepack" ]] \
    && /bin/chmod 755 "$STAGING_APP/Contents/Resources/runtime/bin/corepack"
  if [[ -f "$RUNTIME_DIR/LICENSE-node.txt" ]]; then
    /bin/cp "$RUNTIME_DIR/LICENSE-node.txt" "$STAGING_APP/Contents/Resources/runtime/LICENSE-node.txt"
  elif [[ -f "$RUNTIME_DIR/LICENSE" ]]; then
    /bin/cp "$RUNTIME_DIR/LICENSE" "$STAGING_APP/Contents/Resources/runtime/LICENSE-node.txt"
  fi
fi

/usr/bin/touch "$STAGING_APP"
if [[ -x /usr/bin/xattr ]]; then
  /usr/bin/xattr -cr "$STAGING_APP"
  /usr/bin/xattr -d com.apple.FinderInfo "$STAGING_APP" 2>/dev/null || true
fi
if (( SIGN_APP )) && [[ -x /usr/bin/codesign ]]; then
  /usr/bin/codesign --force --deep --sign - "$STAGING_APP" >/dev/null
  /usr/bin/codesign --verify --deep "$STAGING_APP"
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

if (( SIGN_APP )) && [[ -x /usr/bin/codesign ]]; then
  /usr/bin/codesign --verify --deep "$OUTPUT_APP"
fi
print -- "$OUTPUT_APP"
