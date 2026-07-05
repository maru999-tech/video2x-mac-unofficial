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

# 独自の Bundle ID / 名前を付ける（汎用applet扱いを避け、アイコンキャッシュ対策にも有効）
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :CFBundleIdentifier com.maru999.video2x" "$APP/Contents/Info.plist" 2>/dev/null || \
  "$PB" -c "Add :CFBundleIdentifier string com.maru999.video2x" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleName Video2X" "$APP/Contents/Info.plist" 2>/dev/null || \
  "$PB" -c "Add :CFBundleName string Video2X" "$APP/Contents/Info.plist"

# 3) アイコン適用（バンドルアイコン）
[ -f "$ICNS" ] && cp "$ICNS" "$APP/Contents/Resources/applet.icns"
touch "$APP"

# 3b) カスタムアイコン（リソースフォーク）も付与
#     osacompile アプリは汎用アイコンがキャッシュされやすい。Finderのカスタムアイコン
#     機構で上書きしておくと、キャッシュを迂回して確実に表示される。
if [ -f "$ICNS" ] && command -v Rez >/dev/null 2>&1 && command -v DeRez >/dev/null 2>&1 && command -v SetFile >/dev/null 2>&1; then
  TMPI="$(mktemp -d)"
  if sips -s format png "$ICNS" --out "$TMPI/i.png" >/dev/null 2>&1; then
    sips -i "$TMPI/i.png" >/dev/null 2>&1 || true
    DeRez -only icns "$TMPI/i.png" > "$TMPI/i.rsrc" 2>/dev/null || true
    if [ -s "$TMPI/i.rsrc" ]; then
      ICONFILE="$APP/Icon"$'\r'
      Rez -append "$TMPI/i.rsrc" -o "$ICONFILE" 2>/dev/null || true
      SetFile -a C "$APP" 2>/dev/null || true
      SetFile -a V "$ICONFILE" 2>/dev/null || true
    fi
  fi
  rm -rf "$TMPI"
fi

# 4) LaunchServices に再登録（アイコン反映を確実にする）
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$APP" || true

echo "完成: $APP"
echo "→ Finderで開いて Dock にドラッグしてください:  open -R \"$APP\""
