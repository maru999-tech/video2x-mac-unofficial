# video2x-mac-unofficial

> ⚠️ **Unofficial & independent — NOT the original Video2X.**
> This project is **not affiliated with, endorsed by, or derived from** the original
> [Video2X](https://github.com/k4yt3x/video2x) by k4yt3x. It shares **no code** with it.
> It is a separate macOS shell-script wrapper that drives the **same underlying
> `ncnn-vulkan` engines** (Real-ESRGAN, RIFE). The "video2x" in the name only means it
> performs the same two functions. For the real Video2X, go to the link above.

A tiny, **Apple-Silicon-native** Video2X-*style* CLI for macOS. It does exactly two things — the same two as Video2X — and nothing else:

1. **Super-resolution upscaling** by a **ratio** (Real-ESRGAN, anime/photo models)
2. **Frame interpolation** by a **ratio** (RIFE) for smoother motion

No forced target resolutions, no aspect-ratio changes, no padding. The resolution chosen by the upscale ratio and the fps chosen by the interpolation ratio are written straight to the output.

> Why this exists: the upstream [Video2X](https://github.com/k4yt3x/video2x) is great but historically painful to run on Mac. This is a single shell script around the same `ncnn-vulkan` engines, tuned for Apple Silicon.

🌐 Other languages: [日本語 (README.ja.md)](README.ja.md) · [中文 (README.zh.md)](README.zh.md)

---

## Requirements

- macOS on **Apple Silicon** (M1 or newer recommended; Intel Macs work via MoltenVK but are much slower)
- [Homebrew](https://brew.sh) + ffmpeg: `brew install ffmpeg`

## Install

```bash
git clone https://github.com/maru999-tech/video2x-mac-unofficial.git
cd video2x-mac-unofficial
./setup.sh          # downloads the Real-ESRGAN + RIFE ncnn-vulkan binaries & models
./video2x.sh -h
```

`setup.sh` fetches the third-party binaries from their official GitHub releases (they are **not** bundled in this repo) and clears the macOS quarantine flag.

## GUI (optional)

A tiny local web GUI is included — no upload, native file picker, live progress, trilingual (EN/中/日):

```bash
python3 gui.py        # then a browser tab opens at http://127.0.0.1:8765
```

Or just **double-click `video2x-gui.command`** in Finder. It calls the same `video2x.sh` underneath (Python 3 only, standard library — no extra installs).

## Usage (CLI)

```bash
./video2x.sh -i input.mp4 [-s 2|3|4] [-f N] [-m anime|photo|anime-video] [-x N] [-u on|off] [-r on|off]
```

| Option | Meaning | Default |
|---|---|---|
| `-i FILE` | input video (**required**) | — |
| `-s N` | upscale ratio (`2` / `3` / `4`) | `2` |
| `-f N` | interpolation ratio (integer ≥ 2; e.g. 24→48fps) | `2` |
| `-m MODEL` | `anime` (x4plus-anime, crisp lines) · `photo` (x4plus) · `anime-video` (animevideov3, soft) | `anime` |
| `-x N` | max output long side in px (`0` = unlimited) | `3840` (4K) |
| `-u on\|off` | toggle upscaling | `on` |
| `-r on\|off` | toggle interpolation | `on` |

Output is written next to the input as `<name>_v2x.mp4`.

### Examples

```bash
# Upscale ×2 + interpolate ×2 (default model, 4K cap)
./video2x.sh -i clip.mp4

# Sharper anime, ×2 upscale + 24→60 style smoothing, capped at 5K
./video2x.sh -i clip.mp4 -m anime -s 2 -f 2 -x 5120

# Interpolation only (e.g. 30 → 60 fps), no upscale
./video2x.sh -i clip.mp4 -u off -r on -f 2
```

## How it works

```
input → split to PNG frames + extract audio
      → Real-ESRGAN upscale (model-native scale)
      → [if over the -x cap or model is ×4-only] lanczos downscale to target (supersampling)
      → RIFE interpolate (target frames = frames × ratio)
      → ffmpeg remux at the new fps + original audio
      → auto-delete temp frames → <name>_v2x.mp4
```

Notes:
- **Output fps is derived from real-frames ÷ duration**, not `r_frame_rate`, so **variable-frame-rate (VFR)** sources stay in sync (no "black video while audio keeps playing").
- For ×4-only models (`anime`/`photo`), or when `-s` would exceed the `-x` cap, it upscales large then downscales — which **supersamples** for cleaner edges.
- Audio is copied losslessly when possible.

## Which Macs?

Capability is broad; the difference is mostly **speed** (the binaries auto-tile to fit memory):

| Mac | Works | Feel |
|---|---|---|
| Apple Silicon Pro/Max/Ultra (32GB+) | ✅ | fast |
| Apple Silicon base (16GB) | ✅ | fine, slower |
| Apple Silicon base (8GB) | ✅* | keep resolution modest; the `-x` cap helps |
| Intel + Metal GPU | ⚠️ | works via MoltenVK, slow |

## Credits & License

This project is a wrapper. The heavy lifting is done by:
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) (xinntao) — BSD-3-Clause
- [rife-ncnn-vulkan](https://github.com/nihui/rife-ncnn-vulkan) (nihui) — MIT
- [ncnn](https://github.com/Tencent/ncnn) (Tencent) — BSD-3-Clause
- Inspired by [Video2X](https://github.com/k4yt3x/video2x) (k4yt3x)

Wrapper code: MIT (see [LICENSE](LICENSE)).
