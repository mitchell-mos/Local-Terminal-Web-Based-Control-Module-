#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
SOURCE_SCRIPT="$SCRIPT_DIR/Uninstall.applescript"
SOURCE_ICON="$SCRIPT_DIR/Trash.icns"
OUTPUT_APP="${1:-$REPOSITORY_DIR/Uninstall.app}"

if [[ "${OUTPUT_APP:t}" != "Uninstall.app" ]]; then
  print -u2 -- "The output must be named Uninstall.app."
  exit 1
fi
if [[ ! -f "$SOURCE_SCRIPT" || ! -f "$SOURCE_ICON" ]]; then
  print -u2 -- "The uninstall source or trash icon is missing."
  exit 1
fi

OUTPUT_APP="${OUTPUT_APP:A}"
/bin/mkdir -p "${OUTPUT_APP:h}"
STAGING_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/control-module-uninstall.XXXXXX")"
STAGING_APP="$STAGING_ROOT/Uninstall.app"

cleanup() {
  /bin/rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT HUP INT TERM

/usr/bin/osacompile -o "$STAGING_APP" "$SOURCE_SCRIPT"
/bin/cp "$SOURCE_ICON" "$STAGING_APP/Contents/Resources/Trash.icns"

set_plist_string() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$STAGING_APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$STAGING_APP/Contents/Info.plist"
}

set_plist_string CFBundleDisplayName "Uninstall"
set_plist_string CFBundleName "Uninstall"
set_plist_string CFBundleIdentifier "io.github.mitchell-mos.control-module.uninstall"
set_plist_string CFBundleIconFile "Trash"
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
/usr/libexec/PlistBuddy -c "Add :NSDesktopFolderUsageDescription string Uninstall needs access to the Control Module source folder selected by the user." "$STAGING_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :NSDesktopFolderUsageDescription Uninstall needs access to the Control Module source folder selected by the user." "$STAGING_APP/Contents/Info.plist"

if [[ -e "$OUTPUT_APP" ]]; then
  /bin/mv "$OUTPUT_APP" "$STAGING_ROOT/previous-Uninstall.app"
fi
/bin/mv "$STAGING_APP" "$OUTPUT_APP"
/usr/bin/touch "$OUTPUT_APP"
/usr/bin/xattr -cr "$OUTPUT_APP"
/usr/bin/codesign --force --deep --sign - "$OUTPUT_APP" >/dev/null
/bin/sleep 0.5
/usr/bin/xattr -d com.apple.FinderInfo "$OUTPUT_APP" 2>/dev/null || true
/usr/bin/codesign --verify --deep "$OUTPUT_APP"
print -- "$OUTPUT_APP"
