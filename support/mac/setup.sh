#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
SOURCE_SCRIPT="$SCRIPT_DIR/Setup.applescript"
SOURCE_ICON="$SCRIPT_DIR/App.icns"
OUTPUT_APP="${1:-$REPOSITORY_DIR/Setup.app}"

if [[ "${OUTPUT_APP:t}" != "Setup.app" ]]; then
  print -u2 -- "The output must be named Setup.app."
  exit 1
fi
if [[ ! -f "$SOURCE_SCRIPT" || ! -f "$SOURCE_ICON" ]]; then
  print -u2 -- "The setup source or native gear icon is missing."
  exit 1
fi

OUTPUT_APP="${OUTPUT_APP:A}"
OUTPUT_PARENT="${OUTPUT_APP:h}"
/bin/mkdir -p "$OUTPUT_PARENT"
STAGING_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/control-module-setup.XXXXXX")"
STAGING_APP="$STAGING_ROOT/Setup.app"

cleanup() {
  /bin/rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT HUP INT TERM

/usr/bin/osacompile -o "$STAGING_APP" "$SOURCE_SCRIPT"
/bin/cp "$SOURCE_ICON" "$STAGING_APP/Contents/Resources/ControlModule.icns"

set_plist_string() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$STAGING_APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$STAGING_APP/Contents/Info.plist"
}

set_plist_string CFBundleDisplayName "Setup"
set_plist_string CFBundleName "Setup"
set_plist_string CFBundleIdentifier "io.github.mitchell-mos.control-module.setup"
set_plist_string CFBundleIconFile "ControlModule"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$STAGING_APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :LSMinimumSystemVersionByArchitecture" "$STAGING_APP/Contents/Info.plist" 2>/dev/null || true
for privacy_key in \
  NSAppleEventsUsageDescription \
  NSAppleMusicUsageDescription \
  NSCalendarsUsageDescription \
  NSCameraUsageDescription \
  NSContactsUsageDescription \
  NSHomeKitUsageDescription \
  NSMicrophoneUsageDescription \
  NSPhotoLibraryUsageDescription \
  NSRemindersUsageDescription \
  NSSiriUsageDescription \
  NSSystemAdministrationUsageDescription; do
  /usr/libexec/PlistBuddy -c "Delete :$privacy_key" "$STAGING_APP/Contents/Info.plist" 2>/dev/null || true
done
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$STAGING_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 13.0" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSDesktopFolderUsageDescription string Setup needs access to the source folder you select so it can create and configure the local app." "$STAGING_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :NSDesktopFolderUsageDescription Setup needs access to the source folder you select so it can create and configure the local app." "$STAGING_APP/Contents/Info.plist"

if [[ -e "$OUTPUT_APP" ]]; then
  PREVIOUS_APP="$STAGING_ROOT/previous-Setup.app"
  /bin/mv "$OUTPUT_APP" "$PREVIOUS_APP"
fi
/bin/mv "$STAGING_APP" "$OUTPUT_APP"
/usr/bin/touch "$OUTPUT_APP"
/usr/bin/xattr -cr "$OUTPUT_APP"
/usr/bin/codesign --force --deep --sign - "$OUTPUT_APP" >/dev/null
/bin/sleep 0.5
/usr/bin/xattr -d com.apple.FinderInfo "$OUTPUT_APP" 2>/dev/null || true
/usr/bin/codesign --verify --deep "$OUTPUT_APP"
print -- "$OUTPUT_APP"
