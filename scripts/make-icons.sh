#!/bin/sh
# Renders the app icon and the menu bar template icon from Design/*.svg into the asset catalog.
set -e
cd "$(dirname "$0")/.."
ICON=App/Assets.xcassets/AppIcon.appiconset
BAR=App/Assets.xcassets/MenuBarIcon.imageset
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w $size -h $size Design/ghostly.svg -o "$ICON/icon_$size.png"
done
rsvg-convert -w 18 -h 18 Design/ghostly-menubar.svg -o "$BAR/menubar.png"
rsvg-convert -w 36 -h 36 Design/ghostly-menubar.svg -o "$BAR/menubar@2x.png"
