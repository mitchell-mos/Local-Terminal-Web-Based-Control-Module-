#!/bin/zsh

set -euo pipefail
umask 077

if (( $# != 2 )); then
  print -u2 -- "Usage: $0 SOURCE_DIR CURRENT_SETUP_APP"
  exit 2
fi

SOURCE_DIR="${1:A}"
CURRENT_APP="${2:A}"
TARGET_APP="$SOURCE_DIR/Setup.app"
DESKTOP_APP="$HOME/Desktop/Setup.app"
SETUP_ID="io.github.mitchell-mos.control-module.setup"

bundle_is_setup() {
  local app_path="$1"
  local identifier
  [[ -d "$app_path/Contents" ]] || return 1
  identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$identifier" == "$SETUP_ID" ]]
}

if [[ ! -f "$SOURCE_DIR/package.json" || ! -x "$SOURCE_DIR/support/mac/install.sh" ]]; then
  print -u2 -- "The source folder is not a verified Control Module download."
  exit 1
fi
if [[ "${CURRENT_APP:t}" != "Setup.app" ]] || ! bundle_is_setup "$CURRENT_APP"; then
  print -u2 -- "The running Setup app could not be verified, so it was left where it is."
  exit 1
fi
STAGING_DIR="$(/usr/bin/mktemp -d "$SOURCE_DIR/support/.setup-store.XXXXXX")"
PREVIOUS_APP="$STAGING_DIR/Setup.app"
cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT HUP INT TERM

if [[ "$CURRENT_APP" != "$TARGET_APP" ]]; then
  if [[ -e "$TARGET_APP" ]]; then
    if ! bundle_is_setup "$TARGET_APP"; then
      print -u2 -- "The project Setup.app is not a verified Control Module Setup app, so nothing was moved."
      exit 1
    fi
    /bin/mv "$TARGET_APP" "$PREVIOUS_APP"
  fi

  if ! /bin/mv "$CURRENT_APP" "$TARGET_APP"; then
    [[ -e "$PREVIOUS_APP" ]] && /bin/mv "$PREVIOUS_APP" "$TARGET_APP"
    print -u2 -- "Setup could not be moved into the Control Module folder."
    exit 1
  fi
fi

if [[ -L "$DESKTOP_APP" ]]; then
  /bin/rm "$DESKTOP_APP"
elif [[ -e "$DESKTOP_APP" && "$DESKTOP_APP" != "$CURRENT_APP" ]]; then
  if ! bundle_is_setup "$DESKTOP_APP"; then
    print -u2 -- "A Desktop item named Setup.app is not a verified Control Module Setup app, so it was left unchanged."
    exit 1
  fi
  /bin/mv "$DESKTOP_APP" "$STAGING_DIR/Desktop-Setup.app"
fi

print -- "$TARGET_APP"
