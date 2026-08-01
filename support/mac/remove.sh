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

APPLET_EXECUTABLE="$STAGING_APP/Contents/MacOS/applet"
ARM_APPLET="$STAGING_ROOT/applet-arm64"
if ! /usr/bin/lipo "$APPLET_EXECUTABLE" -verify_arch arm64 >/dev/null 2>&1; then
  print -u2 -- "Uninstall does not contain an Apple silicon arm64 executable."
  exit 1
fi
/usr/bin/lipo "$APPLET_EXECUTABLE" -thin arm64 -output "$ARM_APPLET"
/bin/chmod 755 "$ARM_APPLET"
/bin/mv "$ARM_APPLET" "$APPLET_EXECUTABLE"

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
/usr/libexec/PlistBuddy -c "Delete :LSRequiresCarbon" "$STAGING_APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :LSArchitecturePriority" "$STAGING_APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority array" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority:0 string arm64" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSRequiresNativeExecution bool true" "$STAGING_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSRequiresNativeExecution true" "$STAGING_APP/Contents/Info.plist"
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
/usr/libexec/PlistBuddy -c "Add :NSDesktopFolderUsageDescription string Uninstall moves only the verified Control Module folder containing this app to Trash." "$STAGING_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :NSDesktopFolderUsageDescription Uninstall moves only the verified Control Module folder containing this app to Trash." "$STAGING_APP/Contents/Info.plist"

/usr/bin/touch "$STAGING_APP"
/usr/bin/xattr -cr "$STAGING_APP"
/usr/bin/xattr -d com.apple.FinderInfo "$STAGING_APP" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$STAGING_APP" >/dev/null
/usr/bin/codesign --verify --deep --strict "$STAGING_APP"

if [[ -e "$OUTPUT_APP" ]]; then
  /bin/mv "$OUTPUT_APP" "$STAGING_ROOT/previous-Uninstall.app"
fi
/bin/mv "$STAGING_APP" "$OUTPUT_APP"
# Desktop File Provider may attach external Finder metadata after this cleanup.
# Strict verification above validates the bundle before that filesystem metadata;
# this final check verifies that the installed bundle's signature is unchanged.
/usr/bin/xattr -d com.apple.FinderInfo "$OUTPUT_APP" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "$OUTPUT_APP" 2>/dev/null || true
/usr/bin/codesign --verify --deep "$OUTPUT_APP"
print -- "$OUTPUT_APP"
