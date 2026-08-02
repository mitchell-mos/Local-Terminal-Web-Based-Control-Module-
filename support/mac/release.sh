#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
OUTPUT_DIR="$REPOSITORY_DIR/release"

if [[ "$(/usr/bin/uname -m)" != "arm64" ]]; then
  print -u2 -- "Releases must be built on an Apple silicon Mac."
  exit 1
fi
if ! /usr/bin/git -C "$REPOSITORY_DIR" diff --quiet \
  || ! /usr/bin/git -C "$REPOSITORY_DIR" diff --cached --quiet; then
  print -u2 -- "Commit or stash changes before building a release."
  exit 1
fi

PNPM="$(command -v pnpm || true)"
COREPACK="$(command -v corepack || true)"
run_pnpm() {
  if [[ -n "$PNPM" ]]; then
    "$PNPM" "$@"
  elif [[ -n "$COREPACK" ]]; then
    "$COREPACK" pnpm "$@"
  else
    print -u2 -- "pnpm or Corepack is required to build a release."
    exit 1
  fi
}

cd "$REPOSITORY_DIR"
run_pnpm test
run_pnpm run build

VERSION="v$(/usr/bin/plutil -extract major raw version.json).$(printf '%02d' "$(/usr/bin/plutil -extract update raw version.json)").$(/usr/bin/plutil -extract fix raw version.json)"
STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/control-module-release.XXXXXX")"
PACKAGE_DIR="$STAGING_DIR/Control Module $VERSION"
ARCHIVE_PATH="$OUTPUT_DIR/Control-Module-$VERSION-macOS-arm64.zip"
ARCHIVE_NAME="${ARCHIVE_PATH:t}"

cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT HUP INT TERM

/bin/mkdir -p "$PACKAGE_DIR" "$OUTPUT_DIR"
/usr/bin/git archive --format=tar HEAD | /usr/bin/tar -xf - -C "$PACKAGE_DIR"
/usr/bin/ditto "$REPOSITORY_DIR/dist/standalone" "$PACKAGE_DIR/dist/standalone"
"$PACKAGE_DIR/support/mac/setup.sh" "$PACKAGE_DIR/Setup.app"
"$PACKAGE_DIR/support/mac/remove.sh" "$PACKAGE_DIR/Uninstall.app"
/usr/bin/xattr -cr "$PACKAGE_DIR"
/usr/bin/codesign --verify --deep --strict "$PACKAGE_DIR/Setup.app"
/usr/bin/codesign --verify --deep --strict "$PACKAGE_DIR/Uninstall.app"

/bin/rm -f "$ARCHIVE_PATH" "$ARCHIVE_PATH.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ARCHIVE_PATH"
(
  cd "$OUTPUT_DIR"
  /usr/bin/shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)
print -- "$ARCHIVE_PATH"
