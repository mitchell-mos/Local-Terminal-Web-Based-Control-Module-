#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
SOURCE_NATIVE="$SCRIPT_DIR/Setup.m"
SOURCE_PLIST="$SCRIPT_DIR/Setup.plist"
SOURCE_ICON="$SCRIPT_DIR/App.icns"
OUTPUT_APP="${1:-$REPOSITORY_DIR/Setup.app}"

if [[ "${OUTPUT_APP:t}" != "Setup.app" ]]; then
  print -u2 -- "The output must be named Setup.app."
  exit 1
fi
if [[ ! -f "$SOURCE_NATIVE" || ! -f "$SOURCE_PLIST" || ! -f "$SOURCE_ICON" ]]; then
  print -u2 -- "The native Setup source, property list, or gear icon is missing."
  exit 1
fi
if [[ ! -x "$SCRIPT_DIR/manage.sh" || ! -x "$SCRIPT_DIR/install.sh" ]]; then
  print -u2 -- "The Setup lifecycle or installation backend is missing."
  exit 1
fi

OUTPUT_APP="${OUTPUT_APP:A}"
OUTPUT_PARENT="${OUTPUT_APP:h}"
/bin/mkdir -p "$OUTPUT_PARENT"
STAGING_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/control-module-setup.XXXXXX")"
STAGING_APP="$STAGING_ROOT/Setup.app"
STAGING_EXECUTABLE="$STAGING_APP/Contents/MacOS/Setup"

cleanup() {
  /bin/rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT HUP INT TERM

/bin/mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"
/bin/cp "$SOURCE_PLIST" "$STAGING_APP/Contents/Info.plist"
/bin/cp "$SOURCE_ICON" "$STAGING_APP/Contents/Resources/ControlModule.icns"

VERSION_MAJOR="$(/usr/bin/plutil -extract major raw "$REPOSITORY_DIR/version.json")"
VERSION_UPDATE="$(/usr/bin/plutil -extract update raw "$REPOSITORY_DIR/version.json")"
VERSION_FIX="$(/usr/bin/plutil -extract fix raw "$REPOSITORY_DIR/version.json")"
PLIST_VERSION="$VERSION_MAJOR.$VERSION_UPDATE.$VERSION_FIX"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PLIST_VERSION" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PLIST_VERSION" "$STAGING_APP/Contents/Info.plist"

/usr/bin/xcrun --sdk macosx clang \
  -fobjc-arc \
  -fmodules-cache-path="$STAGING_ROOT/module-cache" \
  -target arm64-apple-macos13.0 \
  -O \
  -framework AppKit \
  -framework Foundation \
  "$SOURCE_NATIVE" \
  -o "$STAGING_EXECUTABLE"
/bin/chmod 755 "$STAGING_EXECUTABLE"

if ! /usr/bin/lipo "$STAGING_EXECUTABLE" -verify_arch arm64 >/dev/null 2>&1; then
  print -u2 -- "Setup does not contain an Apple silicon arm64 executable."
  exit 1
fi

/usr/bin/touch "$STAGING_APP"
/usr/bin/xattr -cr "$STAGING_APP"
/usr/bin/xattr -d com.apple.FinderInfo "$STAGING_APP" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$STAGING_APP" >/dev/null
/usr/bin/codesign --verify --deep --strict "$STAGING_APP"

if [[ -e "$OUTPUT_APP" ]]; then
  /bin/mv "$OUTPUT_APP" "$STAGING_ROOT/previous-Setup.app"
fi
/bin/mv "$STAGING_APP" "$OUTPUT_APP"
/usr/bin/xattr -d com.apple.FinderInfo "$OUTPUT_APP" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "$OUTPUT_APP" 2>/dev/null || true
/usr/bin/codesign --verify --deep "$OUTPUT_APP"
print -- "$OUTPUT_APP"
