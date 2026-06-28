#!/bin/bash
#
# setup.sh - video2x-mac のセットアップ
#   Real-ESRGAN / RIFE の Apple Silicon 対応 ncnn-vulkan バイナリ＆モデルを取得します。
#   （バイナリ・モデルはリポジトリには含めず、ここで公式リリースから取得します）
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$SCRIPT_DIR/tools"
mkdir -p "$TOOLS"
cd "$TOOLS"

REALESRGAN_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"
RIFE_URL="https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-macos.zip"

echo "==> ffmpeg の確認"
command -v ffmpeg  >/dev/null || { echo "!! ffmpeg が見つかりません。 brew install ffmpeg を実行してください"; exit 1; }
command -v ffprobe >/dev/null || { echo "!! ffprobe が見つかりません。 brew install ffmpeg を実行してください"; exit 1; }

if [ ! -x "$TOOLS/realesrgan/realesrgan-ncnn-vulkan" ]; then
  echo "==> Real-ESRGAN ncnn-vulkan (macOS) をダウンロード"
  curl -L --fail -o realesrgan.zip "$REALESRGAN_URL"
  mkdir -p realesrgan && unzip -o -q realesrgan.zip -d realesrgan && rm -f realesrgan.zip
else
  echo "==> Real-ESRGAN は導入済み"
fi

if [ ! -x "$TOOLS/rife/rife-ncnn-vulkan-20221029-macos/rife-ncnn-vulkan" ]; then
  echo "==> RIFE ncnn-vulkan (macOS) をダウンロード"
  curl -L --fail -o rife.zip "$RIFE_URL"
  mkdir -p rife && unzip -o -q rife.zip -d rife && rm -f rife.zip
else
  echo "==> RIFE は導入済み"
fi

echo "==> macOS の検疫属性を解除し、実行権限を付与"
xattr -dr com.apple.quarantine "$TOOLS" 2>/dev/null || true
chmod +x "$TOOLS/realesrgan/realesrgan-ncnn-vulkan" \
         "$TOOLS/rife/rife-ncnn-vulkan-20221029-macos/rife-ncnn-vulkan" 2>/dev/null || true

echo
echo "==> 完了。使い方:  $SCRIPT_DIR/video2x.sh -h"
echo "    例:  $SCRIPT_DIR/video2x.sh -i input.mp4 -m anime -s 2 -f 2"
