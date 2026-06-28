#!/bin/bash
#
# video2x.sh - Video2X 同等のローカル処理（macOS / Apple Silicon）
#
#   機能はVideo2Xと同じ2つだけ:
#     (1) 超解像アップスケール: Real-ESRGAN(realesr-animevideov3) で「倍率」拡大
#     (2) フレーム補間:        RIFE(rife-v4.6) で「倍率」分フレームレートを上げる
#
#   解像度のリサイズ/アスペクト比変更/パディング等の追加加工は一切しない。
#   アップスケールで決まった解像度、補間で決まったfpsを、そのまま出力に反映する。
#
# 使い方:
#   video2x.sh -i 入力.mp4 [-s 2] [-f 2] [-m anime] [-u on|off] [-r on|off]
#
#   -i FILE   入力動画ファイル（必須）
#   -s N      アップスケール倍率（2 / 3 / 4。既定: 2）
#   -f N      補間倍率（2以上の整数。例: 2 なら 24fps→48fps。既定: 2）
#   -m MODEL  アップスケールのモデル（既定: anime）
#               anime-video … realesr-animevideov3（柔らかい・低画質アニメ動画の整え向け）
#               anime       … realesrgan-x4plus-anime（アニメ絵がくっきり・既定）
#               photo       … realesrgan-x4plus（実写寄り・質感多め）
#             ※anime / photo は ×4 専用モデル。指定倍率が4未満なら ×4 後に高品質縮小して合わせます
#   -x N      出力の長辺の上限px（既定: 3840=4K, 0=無制限）
#             「元×倍率」がこれを超えたら、モデルのネイティブ倍率で大きく生成してから
#             上限サイズへlanczos縮小（スーパーサンプリング）。出力が巨大化しないための上限。
#   -u on|off アップスケールのオン/オフ（既定: on）
#   -r on|off フレーム補間のオン/オフ（既定: on）
#
#   出力: 入力と同じフォルダに  元ファイル名_v2x.mp4
#
set -euo pipefail

# ---- ツールの場所（必要なら環境変数で上書き可） ---------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${VIDEO2X_TOOLS:-$SCRIPT_DIR/tools}"
REALESRGAN_BIN="${REALESRGAN_BIN:-$TOOLS_DIR/realesrgan/realesrgan-ncnn-vulkan}"
REALESRGAN_MODELS="${REALESRGAN_MODELS:-$TOOLS_DIR/realesrgan/models}"
RIFE_BIN="${RIFE_BIN:-$TOOLS_DIR/rife/rife-ncnn-vulkan-20221029-macos/rife-ncnn-vulkan}"
RIFE_MODEL="${RIFE_MODEL:-$TOOLS_DIR/rife/rife-ncnn-vulkan-20221029-macos/rife-v4.6}"

# ---- 既定の引数 ------------------------------------------------------------
INPUT=""
SCALE=2
FACTOR=2
DO_UPSCALE="on"
DO_INTERP="on"
MODEL_KEY="anime"     # anime-video / anime / photo（-m で変更）
MAX_LONG=3840         # 出力の長辺上限px（-x で変更, 0=無制限）。既定4K

# ---- 進捗表示用 ------------------------------------------------------------
log()  { printf '\033[1;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
err()  { printf '\033[1;31m[エラー]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---- 引数パース ------------------------------------------------------------
while getopts ":i:s:f:u:r:m:x:h" opt; do
  case "$opt" in
    i) INPUT="$OPTARG" ;;
    s) SCALE="$OPTARG" ;;
    f) FACTOR="$OPTARG" ;;
    u) DO_UPSCALE="$OPTARG" ;;
    r) DO_INTERP="$OPTARG" ;;
    m) MODEL_KEY="$OPTARG" ;;
    x) MAX_LONG="$OPTARG" ;;
    h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    \?) die "不明なオプション: -$OPTARG （-h でヘルプ）" ;;
    :)  die "オプション -$OPTARG には値が必要です" ;;
  esac
done
case "$MAX_LONG" in ''|*[!0-9]*) die "-x（長辺上限px）は0以上の整数で指定してください（0=無制限）" ;; esac

# 使うモデルとその「ネイティブ倍率」を決める
#   anime-video : realesr-animevideov3   ネイティブ 2/3/4（柔らかい・低画質動画向け）
#   anime       : realesrgan-x4plus-anime ネイティブ ×4 のみ（アニメ絵がくっきり）
#   photo       : realesrgan-x4plus       ネイティブ ×4 のみ（実写寄り・質感多め）
case "$MODEL_KEY" in
  anime-video|animevideo|animevideov3|realesr-animevideov3)
      UPSCALE_MODEL="realesr-animevideov3"; MODEL_NATIVE="var" ;;
  anime|x4plus-anime|realesrgan-x4plus-anime)
      UPSCALE_MODEL="realesrgan-x4plus-anime"; MODEL_NATIVE=4 ;;
  photo|x4plus|realesrgan-x4plus)
      UPSCALE_MODEL="realesrgan-x4plus"; MODEL_NATIVE=4 ;;
  *) die "不明なモデル(-m): $MODEL_KEY （anime-video / anime / photo のいずれか）" ;;
esac

# ---- 入力チェック ----------------------------------------------------------
[ -n "$INPUT" ] || die "入力ファイルを -i で指定してください（-h でヘルプ）"
[ -f "$INPUT" ] || die "入力ファイルが見つかりません: $INPUT"
case "$DO_UPSCALE" in on|off) ;; *) die "-u は on か off です" ;; esac
case "$DO_INTERP"  in on|off) ;; *) die "-r は on か off です" ;; esac
if [ "$DO_UPSCALE" = "on" ]; then
  case "$SCALE" in 2|3|4) ;; *) die "アップスケール倍率(-s)は 2/3/4 のいずれかです（realesr-animevideov3の対応倍率）" ;; esac
fi
if [ "$DO_INTERP" = "on" ]; then
  case "$FACTOR" in ''|*[!0-9]*) die "補間倍率(-f)は整数で指定してください" ;; esac
  [ "$FACTOR" -ge 2 ] || die "補間倍率(-f)は2以上にしてください"
fi
command -v ffmpeg  >/dev/null || die "ffmpeg が見つかりません（brew install ffmpeg）"
command -v ffprobe >/dev/null || die "ffprobe が見つかりません"
[ "$DO_UPSCALE" = "off" ] || [ -x "$REALESRGAN_BIN" ] || die "realesrgan が見つかりません: $REALESRGAN_BIN"
[ "$DO_INTERP"  = "off" ] || [ -x "$RIFE_BIN" ]       || die "rife が見つかりません: $RIFE_BIN"

# ---- 出力パスと作業ディレクトリ --------------------------------------------
IN_DIR="$(cd "$(dirname "$INPUT")" && pwd)"
IN_BASE="$(basename "$INPUT")"
IN_STEM="${IN_BASE%.*}"
OUTPUT="$IN_DIR/${IN_STEM}_v2x.mp4"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/video2x.XXXXXX")"
F_RAW="$WORK/01_frames"        # 元フレーム
F_UP="$WORK/02_upscaled"       # アップスケール後
F_INT="$WORK/03_interp"        # 補間後
AUDIO="$WORK/audio.m4a"
mkdir -p "$F_RAW" "$F_UP" "$F_INT"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---- 入力情報の取得 --------------------------------------------------------
# 実再生時間に合うフレームレートを使う。
#   avg_frame_rate = 総フレーム数 / 再生時間 で、CFRでもVFRでも「実効fps」になる。
#   r_frame_rate は VFR動画だと実効値より極端に大きい事があり、出力が破綻するため使わない。
DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" | tr -d '[:space:]')"
AFR="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$INPUT" | tr -d '[:space:]')"
RFR="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate   -of csv=p=0 "$INPUT" | tr -d '[:space:]')"

# avg_frame_rate を第一候補に、空/0分母なら r_frame_rate にフォールバック
FPS_FRAC=""
for cand in "$AFR" "$RFR"; do
  n="${cand%/*}"; d="${cand#*/}"
  [ "$d" = "$cand" ] && d=1
  case "$n" in ''|0|*[!0-9]*) continue ;; esac
  case "$d" in ''|0|*[!0-9]*) continue ;; esac
  FPS_FRAC="$cand"; FPS_NUM="$n"; FPS_DEN="$d"; break
done
# どちらもダメなら nb_frames/duration から実測
if [ -z "$FPS_FRAC" ]; then
  NBF="$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$INPUT" | tr -d '[:space:]')"
  case "$NBF" in ''|*[!0-9]*) NBF="" ;; esac
  if [ -n "$NBF" ] && [ -n "$DURATION" ]; then
    FPS_NUM="$(awk "BEGIN{printf \"%d\", ($NBF/$DURATION)*1000}")"
    FPS_DEN=1000
    FPS_FRAC="${FPS_NUM}/${FPS_DEN}"
  else
    die "入力のフレームレートを取得できませんでした"
  fi
fi
FPS_DISP="$(awk "BEGIN{printf \"%.3f\", $FPS_NUM/$FPS_DEN}")"
HAS_AUDIO="$(ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$INPUT" | head -n1)"

echo
log "==== Video2X 同等処理を開始 ===="
log "入力           : $INPUT"
log "元フレームレート: ${FPS_DISP} fps"
log "アップスケール  : $([ "$DO_UPSCALE" = on ] && echo "ON（×${SCALE}, ${UPSCALE_MODEL}）" || echo "OFF")"
log "解像度上限      : $([ "$MAX_LONG" -gt 0 ] && echo "長辺 ${MAX_LONG}px（超過分は縮小）" || echo "無制限")"
log "フレーム補間    : $([ "$DO_INTERP"  = on ] && echo "ON（×${FACTOR}, rife-v4.6）" || echo "OFF")"
log "出力           : $OUTPUT"
log "作業フォルダ    : $WORK"
echo

# ---- 1. フレーム分解 + 音声抽出 --------------------------------------------
log "[1/5] 動画をフレーム(連番PNG)に分解しています..."
ffmpeg -hide_banner -loglevel error -i "$INPUT" -vsync 0 "$F_RAW/%08d.png"
NFRAMES="$(find "$F_RAW" -name '*.png' | wc -l | tr -d ' ')"
[ "$NFRAMES" -gt 0 ] || die "フレームを抽出できませんでした"
ORIG_DIM="$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$(find "$F_RAW" -name '*.png' | sort | head -n1)")"
ORIG_W="${ORIG_DIM%,*}"; ORIG_H="${ORIG_DIM#*,}"
log "      → ${NFRAMES} フレームを抽出しました（元解像度: ${ORIG_W}x${ORIG_H}）"

if [ -n "$HAS_AUDIO" ]; then
  log "      音声トラックを抽出しています..."
  # まずは無劣化コピーを試し、ダメなら AAC で再エンコード
  if ffmpeg -hide_banner -loglevel error -i "$INPUT" -vn -c:a copy "$AUDIO" 2>/dev/null; then
    log "      → 音声を無劣化で抽出しました"
  else
    ffmpeg -hide_banner -loglevel error -i "$INPUT" -vn -c:a aac -b:a 192k "$AUDIO"
    log "      → 音声をAACで抽出しました"
  fi
else
  log "      → 音声トラックなし"
fi

# ---- 2. アップスケール（Real-ESRGAN） --------------------------------------
SRC_FOR_INTERP="$F_RAW"
if [ "$DO_UPSCALE" = "on" ]; then
  # 最終出力サイズを決める: まず「元×倍率」、長辺が上限を超えたら上限へ収める（偶数化）
  FINAL_W=$(( ORIG_W * SCALE )); FINAL_H=$(( ORIG_H * SCALE ))
  CAPPED="no"
  if [ "$MAX_LONG" -gt 0 ]; then
    LONGSIDE=$FINAL_W; [ "$FINAL_H" -gt "$FINAL_W" ] && LONGSIDE=$FINAL_H
    if [ "$LONGSIDE" -gt "$MAX_LONG" ]; then
      FINAL_W=$(awk "BEGIN{v=$FINAL_W*$MAX_LONG/$LONGSIDE; printf \"%d\", int(v/2)*2}")
      FINAL_H=$(awk "BEGIN{v=$FINAL_H*$MAX_LONG/$LONGSIDE; printf \"%d\", int(v/2)*2}")
      CAPPED="yes"
    fi
  fi

  # モデルのネイティブ倍率で「大きく」作る（animevideov3は2/3/4、x4plus系は×4のみ）
  if [ "$MODEL_NATIVE" = "var" ]; then RUN_SCALE="$SCALE"; else RUN_SCALE="$MODEL_NATIVE"; fi
  UP_W=$(( ORIG_W * RUN_SCALE )); UP_H=$(( ORIG_H * RUN_SCALE ))
  if [ "$CAPPED" = "yes" ]; then
    log "[2/5] Real-ESRGAN(${UPSCALE_MODEL}) ×${RUN_SCALE} で生成 → 上限${MAX_LONG}pxに合わせ ${FINAL_W}x${FINAL_H} へ縮小します（元×${SCALE}=${UP_W}x${UP_H}相当を上限で制限）..."
  else
    log "[2/5] Real-ESRGAN(${UPSCALE_MODEL}) で各フレームを ×${RUN_SCALE} アップスケールしています..."
  fi
  "$REALESRGAN_BIN" -i "$F_RAW" -o "$F_UP" -s "$RUN_SCALE" -n "$UPSCALE_MODEL" -m "$REALESRGAN_MODELS"
  UPN="$(find "$F_UP" -name '*.png' | wc -l | tr -d ' ')"
  [ "$UPN" -eq "$NFRAMES" ] || die "アップスケール後のフレーム数が一致しません（$UPN/$NFRAMES）"
  SRC_FOR_INTERP="$F_UP"

  # ネイティブ生成サイズが最終サイズと違えば、最終サイズへ高品質縮小（lanczos＝スーパーサンプリング）
  if [ "$UP_W" != "$FINAL_W" ] || [ "$UP_H" != "$FINAL_H" ]; then
    log "      → ×${RUN_SCALE}（${UP_W}x${UP_H}）完了。最終 ${FINAL_W}x${FINAL_H} へ縮小しています..."
    F_DS="$WORK/02b_downscaled"; mkdir -p "$F_DS"
    ffmpeg -hide_banner -loglevel error -y -i "$F_UP/%08d.png" \
      -vf "scale=${FINAL_W}:${FINAL_H}:flags=lanczos" "$F_DS/%08d.png"
    SRC_FOR_INTERP="$F_DS"
  fi
  DIM="$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$(find "$SRC_FOR_INTERP" -name '*.png' | sort | head -n1)")"
  log "      → 完了（アップスケール後の解像度: ${DIM}）"
else
  log "[2/5] アップスケールは OFF のためスキップします"
fi

# ---- 3. フレーム補間（RIFE） -----------------------------------------------
SRC_FOR_MUX="$SRC_FOR_INTERP"
OUT_FPS_NUM="$FPS_NUM"
if [ "$DO_INTERP" = "on" ]; then
  TARGET=$(( NFRAMES * FACTOR ))
  OUT_FPS_NUM=$(( FPS_NUM * FACTOR ))
  OUT_FPS_DISP="$(awk "BEGIN{printf \"%.3f\", $OUT_FPS_NUM/$FPS_DEN}")"
  log "[3/5] RIFE(rife-v4.6) で ×${FACTOR} フレーム補間しています（${NFRAMES}→${TARGET}フレーム, ${FPS_DISP}→${OUT_FPS_DISP} fps）..."
  "$RIFE_BIN" -i "$SRC_FOR_INTERP" -o "$F_INT" -m "$RIFE_MODEL" -n "$TARGET"
  INTN="$(find "$F_INT" -name '*.png' | wc -l | tr -d ' ')"
  log "      → 完了（${INTN} フレーム生成）"
  SRC_FOR_MUX="$F_INT"
else
  log "[3/5] フレーム補間は OFF のためスキップします"
fi

# ---- 4. 再結合（FFmpeg）＋音声を戻す ---------------------------------------
# 出力fpsは「最終フレーム数 ÷ 入力の実再生時間」で直接決める。
# こうすると映像の長さが必ず入力（=音声）と一致し、VFR入力でも破綻しない。
MUX_FRAMES="$(find "$SRC_FOR_MUX" -name '*.png' | wc -l | tr -d ' ')"
if [ -n "$DURATION" ] && awk "BEGIN{exit !($DURATION>0)}"; then
  OUT_FPS_FRAC="$(awk "BEGIN{printf \"%.6f\", $MUX_FRAMES/$DURATION}")"
else
  OUT_FPS_FRAC="${OUT_FPS_NUM}/${FPS_DEN}"   # 再生時間が取れない時のフォールバック
fi
OUT_FPS_DISP="$(awk "BEGIN{printf \"%.3f\", $OUT_FPS_FRAC + 0}")"
log "[4/5] FFmpeg でフレームを再結合しています（${MUX_FRAMES}フレーム → 出力 ${OUT_FPS_DISP} fps）..."

MUX_AUDIO_IN=()
MUX_AUDIO_MAP=()
if [ -n "$HAS_AUDIO" ] && [ -f "$AUDIO" ]; then
  MUX_AUDIO_IN=(-i "$AUDIO")
  MUX_AUDIO_MAP=(-map 0:v:0 -map 1:a:0 -c:a copy)
fi

# 解像度/アスペクト比は触らず、フレームをそのまま符号化する
ffmpeg -hide_banner -loglevel error -y \
  -framerate "$OUT_FPS_FRAC" \
  -i "$SRC_FOR_MUX/%08d.png" \
  "${MUX_AUDIO_IN[@]}" \
  "${MUX_AUDIO_MAP[@]}" \
  -c:v libx264 -pix_fmt yuv420p -crf 16 -preset slow \
  -r "$OUT_FPS_FRAC" \
  "$OUTPUT"
log "      → 書き出し完了"

# ---- 5. 後始末（中間ファイル削除） -----------------------------------------
log "[5/5] 中間ファイル(連番PNG)を削除しています..."
# trap で WORK ごと削除される
FINAL_DIM="$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$OUTPUT")"
FINAL_FPS="$(ffprobe -v error -select_streams v -show_entries stream=r_frame_rate -of csv=p=0 "$OUTPUT" | tr -d '[:space:]')"
echo
log "==== 完了 ===="
log "出力ファイル : $OUTPUT"
log "解像度       : ${FINAL_DIM}"
log "フレームレート: ${FINAL_FPS}"
echo
