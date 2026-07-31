#!/bin/zsh

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPOSITORY_DIR="${SCRIPT_DIR:h:h}"
SOURCE_SVG="${1:-$REPOSITORY_DIR/public/gear.svg}"
OUTPUT_ICNS="${2:-$SCRIPT_DIR/App.icns}"

for required_tool in /usr/bin/qlmanage /usr/bin/sips /usr/bin/iconutil; do
  if [[ ! -x "$required_tool" ]]; then
    print -u2 -- "Required macOS tool not found: $required_tool"
    exit 1
  fi
done

if [[ ! -f "$SOURCE_SVG" ]]; then
  print -u2 -- "The icon source was not found at $SOURCE_SVG"
  exit 1
fi

SOURCE_SVG="${SOURCE_SVG:A}"
OUTPUT_ICNS="${OUTPUT_ICNS:A}"
WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/control-module-icon.XXXXXX")"
ICONSET_DIR="$WORK_DIR/ControlModule.iconset"
SCALABLE_SVG="$WORK_DIR/gear.svg"

cleanup() {
  /bin/rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

/bin/mkdir -p "$ICONSET_DIR" "${OUTPUT_ICNS:A:h}"
/usr/bin/sed -E 's/width="[^"]+" height="[^"]+"/width="1024" height="1024"/' "$SOURCE_SVG" > "$SCALABLE_SVG"
/usr/bin/qlmanage -t -s 1024 -o "$WORK_DIR" "$SCALABLE_SVG" >/dev/null
SOURCE_PNG="$WORK_DIR/gear.svg.png"

if [[ ! -f "$SOURCE_PNG" ]]; then
  print -u2 -- "macOS could not render the web gear icon."
  exit 1
fi

/usr/bin/sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
/bin/cp "$SOURCE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
print -- "$OUTPUT_ICNS"
