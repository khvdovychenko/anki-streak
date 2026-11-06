#!/bin/bash
# Renders Cinder's images with headless Chrome into the asset catalog.
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
A=Shared/Assets.xcassets
render() { "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --window-size=$3,$3 --screenshot="$2" "file://$PWD/tools/render.html?$1" >/dev/null 2>&1; }
for s in 0 1 2 3 4 5; do
  if [ $s = 0 ]; then moods="dead"; else moods="lit partial fading dying dead"; fi
  for m in $moods; do
    n="cinder-$s-$m"; mkdir -p "$A/$n.imageset"
    render "s=$s&m=$m" "$A/$n.imageset/$n.png" 360
    printf '{"images":[{"filename":"%s.png","idiom":"universal","scale":"3x"}],"info":{"author":"xcode","version":1}}' "$n" > "$A/$n.imageset/Contents.json"
  done
done
render "icon=1" "$A/AppIcon.appiconset/icon-1024.png" 1024
sips -s format png --deleteProperty all "$A/AppIcon.appiconset/icon-1024.png" >/dev/null 2>&1 || true
echo "assets done: $(ls -d $A/cinder-*.imageset | wc -l) images"
