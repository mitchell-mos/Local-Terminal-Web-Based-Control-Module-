#!/bin/zsh

set -euo pipefail
umask 077

if (( $# != 2 )); then
  print -u2 -- "Usage: $0 SOURCE_DIR CURRENT_SETUP_APP"
  exit 2
fi

SOURCE_DIR="${1:A}"
CURRENT_APP="${2:A}"
TARGET_APP="$SOURCE_DIR/support/Setup.app"
ROOT_APP="$SOURCE_DIR/Setup.app"
SETUP_ID="io.github.mitchell-mos.control-module.setup"

bundle_is_setup() {
  local app_path="$1"
  local identifier
  [[ -d "$app_path/Contents" ]] || return 1
  identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$identifier" == "$SETUP_ID" ]]
}

if [[ ! -f "$SOURCE_DIR/package.json" || ! -x "$SOURCE_DIR/support/mac/install.sh" ]]; then
  print -u2 -- "The selected source folder is not a complete Control Module download."
  exit 1
fi
if [[ "${CURRENT_APP:t}" != "Setup.app" ]] || ! bundle_is_setup "$CURRENT_APP"; then
  print -u2 -- "The running Setup app could not be verified, so it was left where it is."
  exit 1
fi
if [[ "$ROOT_APP" != "$CURRENT_APP" && "$ROOT_APP" != "$TARGET_APP" && -e "$ROOT_APP" ]] \
  && ! bundle_is_setup "$ROOT_APP"; then
  print -u2 -- "The root Setup.app was not recognized, so nothing was moved."
  exit 1
fi

if [[ "$CURRENT_APP" != "$TARGET_APP" ]]; then
  STAGING_DIR="$(/usr/bin/mktemp -d "$SOURCE_DIR/support/.setup-store.XXXXXX")"
  PREVIOUS_APP="$STAGING_DIR/Setup.app"
  cleanup() {
    /bin/rm -rf "$STAGING_DIR"
  }
  trap cleanup EXIT HUP INT TERM

  if [[ -e "$TARGET_APP" ]]; then
    if ! bundle_is_setup "$TARGET_APP"; then
      print -u2 -- "support/Setup.app is not a verified Control Module Setup app, so nothing was moved."
      exit 1
    fi
    /bin/mv "$TARGET_APP" "$PREVIOUS_APP"
  fi

  if ! /bin/mv "$CURRENT_APP" "$TARGET_APP"; then
    [[ -e "$PREVIOUS_APP" ]] && /bin/mv "$PREVIOUS_APP" "$TARGET_APP"
    print -u2 -- "Setup could not be moved into the support folder."
    exit 1
  fi
fi

if [[ "$ROOT_APP" != "$TARGET_APP" && "$ROOT_APP" != "$CURRENT_APP" && -e "$ROOT_APP" ]]; then
  /bin/rm -rf "$ROOT_APP"
fi

print -- "$TARGET_APP"
