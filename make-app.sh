#!/bin/bash
#
# make-app.sh - Dock 用の Video2X.app（アイコン付きランチャー）を生成する
#   icon.svg から icns を作り、gui.py を起動する .app を組み立てます。
#   macOS 標準ツール（qlmanage / sips / iconutil / osacompile）のみ使用。
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$HERE/icon.svg"
ICNS="$HERE/Video2X.icns"
APP="$HERE/Video2X.app"

# 1) icon.svg → 1024px PNG（QuickLook）→ iconset → icns
if [ -f "$SVG" ]; then
  TMP="$(mktemp -d)"
  qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1 || true
  PNG="$(ls "$TMP"/*.png 2>/dev/null | head -1 || true)"
  if [ -n "$PNG" ]; then
    ISET="$TMP/Video2X.iconset"; mkdir -p "$ISET"
    for sz in 16 32 128 256 512; do
      sips -z $sz $sz "$PNG" --out "$ISET/icon_${sz}x${sz}.png" >/dev/null
      sips -z $((sz*2)) $((sz*2)) "$PNG" --out "$ISET/icon_${sz}x${sz}@2x.png" >/dev/null
    done
    cp "$PNG" "$ISET/icon_512x512@2x.png"
    iconutil -c icns "$ISET" -o "$ICNS"
  fi
  rm -rf "$TMP"
fi

# 2) gui.py を起動するランチャーアプリ
rm -rf "$APP"
osacompile -o "$APP" -e "do shell script \"nohup /usr/bin/python3 '$HERE/gui.py' >/tmp/v2xgui.log 2>&1 &\""

# 3) アイコン適用
[ -f "$ICNS" ] && cp "$ICNS" "$APP/Contents/Resources/applet.icns"
touch "$APP"

echo "完成: $APP"
echo "→ Finderで開いて Dock にドラッグしてください:  open -R \"$APP\""
