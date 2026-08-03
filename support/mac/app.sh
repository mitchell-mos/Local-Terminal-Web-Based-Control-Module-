#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
SOURCE_DIR="$REPOSITORY_DIR"
OUTPUT_APP="$REPOSITORY_DIR/release/Control Module.app"
RUNTIME_DIR=""
INSTANCE_ID=""
SIGN_APP=1
SOURCE_LAUNCHER="$SCRIPT_DIR/Launch.applescript"

usage() {
  print -- "Usage: $0 [--source DIR] [--output APP] [--runtime DIR] [--instance-id UUID] [--no-sign]"
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
    --instance-id)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      INSTANCE_ID="$2"
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

if [[ ! -f "$SOURCE_DIR/package.json" || ! -f "$SOURCE_DIR/version.json" || ! -x "$SOURCE_DIR/ControlModule" || ! -f "$SOURCE_DIR/server/control_server.py" || ! -f "$SOURCE_LAUNCHER" ]]; then
  print -u2 -- "The source folder must contain the Control Module launcher, package, version, server, and native launcher source."
  exit 1
fi

if [[ "${OUTPUT_APP:t}" != "Control Module.app" ]] \
  && ! print -r -- "${OUTPUT_APP:t}" | /usr/bin/grep -Eq '^Control Module [a-f0-9]{8}\.app$'; then
  print -u2 -- "The output must be named Control Module.app or use its eight-character installation suffix."
  exit 1
fi
if [[ -n "$INSTANCE_ID" ]] \
  && ! print -r -- "$INSTANCE_ID" | /usr/bin/grep -Eq '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'; then
  print -u2 -- "The internal installation marker must be a lowercase UUIDv4."
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
VERSION_MAJOR="$(/usr/bin/plutil -extract major raw "$SOURCE_DIR/version.json")"
VERSION_UPDATE="$(/usr/bin/plutil -extract update raw "$SOURCE_DIR/version.json")"
VERSION_FIX="$(/usr/bin/plutil -extract fix raw "$SOURCE_DIR/version.json")"
PLIST_VERSION="$VERSION_MAJOR.$VERSION_UPDATE.$VERSION_FIX"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PLIST_VERSION" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PLIST_VERSION" "$STAGING_APP/Contents/Info.plist"
if [[ -n "$INSTANCE_ID" ]]; then
  print -r -- "$INSTANCE_ID" > "$STAGING_APP/Contents/Resources/instance-id"
  /bin/chmod 600 "$STAGING_APP/Contents/Resources/instance-id"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.mitchell-mos.control-module.instance.$INSTANCE_ID" "$STAGING_APP/Contents/Info.plist"
fi

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
  /usr/bin/codesign --verify --deep --strict "$STAGING_APP"
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
  # Desktop File Provider may attach external Finder metadata after this cleanup.
  # Strict verification above validates the bundle before that filesystem metadata;
  # this final check verifies that the installed bundle's signature is unchanged.
  /usr/bin/xattr -d com.apple.FinderInfo "$OUTPUT_APP" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.ResourceFork "$OUTPUT_APP" 2>/dev/null || true
  /usr/bin/codesign --verify --deep "$OUTPUT_APP"
fi
print -- "$OUTPUT_APP"
