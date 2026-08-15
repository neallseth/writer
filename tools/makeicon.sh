#!/bin/zsh
# Regenerates Assets/AppIcon.icns from tools/makeicon.swift.
set -e
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

swiftc tools/makeicon.swift -o "$TMP/makeicon" -framework AppKit
"$TMP/makeicon" "$TMP/icon-1024.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$TMP/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$TMP/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p Assets
iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
echo "Wrote Assets/AppIcon.icns"
