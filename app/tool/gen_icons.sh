#!/bin/sh
# アイコンの元絵（assets/icon/app_icon.svg）から、macOS と Windows のアイコンを作る。
# 要るもの: rsvg-convert（librsvg）と ImageMagick。app/ で実行する。
#   brew install librsvg imagemagick
set -eu
cd "$(dirname "$0")/.."
svg=assets/icon/app_icon.svg
mac=macos/Runner/Assets.xcassets/AppIcon.appiconset
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# macOS: 余白つきの角丸（macOS の他のアイコンと大きさをそろえる）。
for s in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$s" -h "$s" "$svg" -o "$mac/app_icon_$s.png"
done

# Windows: 余白を切り落として大きく見せる。
sed 's/viewBox="0 0 1024 1024"/viewBox="100 100 824 824"/' "$svg" > "$tmp/win.svg"
for s in 16 24 32 48 64 128 256; do
  rsvg-convert -w "$s" -h "$s" "$tmp/win.svg" -o "$tmp/$s.png"
done
magick "$tmp"/16.png "$tmp"/24.png "$tmp"/32.png "$tmp"/48.png "$tmp"/64.png \
  "$tmp"/128.png "$tmp"/256.png windows/runner/resources/app_icon.ico
