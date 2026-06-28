# video2x-mac-unofficial

> ⚠️ **非官方 · 独立项目 — 不是原版 Video2X。**
> 本项目与 k4yt3x 的原版 [Video2X](https://github.com/k4yt3x/video2x) **没有任何隶属、
> 认可或衍生关系**，也**不共享任何代码**。它只是一个面向 macOS 的独立 Shell 脚本，调用与原版
> **相同的底层 `ncnn-vulkan` 引擎**（Real-ESRGAN、RIFE）。名字里的 “video2x” 仅表示它做
> 同样的两件事。需要真正的 Video2X，请前往上方链接。

一个极简、**原生支持 Apple Silicon** 的 Video2X *风格* macOS 命令行工具。它只做两件事——和 Video2X 一样的两件——别无其他：

1. **超分辨率放大**：按**倍率**放大（Real-ESRGAN，动漫/写实模型）
2. **补帧**：按**倍率**提高帧率（RIFE），让动作更流畅

不强制目标分辨率、不改变宽高比、不加黑边。放大倍率决定的分辨率、补帧倍率决定的帧率，会原样写入输出。

🌐 其他语言：[English (README.md)](README.md) · [日本語 (README.ja.md)](README.ja.md)

---

## 环境要求

- **Apple Silicon** 的 macOS（建议 M1 及更新；Intel Mac 可通过 MoltenVK 运行，但慢很多）
- [Homebrew](https://brew.sh) + ffmpeg：`brew install ffmpeg`

## 安装

```bash
git clone https://github.com/maru999-tech/video2x-mac-unofficial.git
cd video2x-mac-unofficial
./setup.sh          # 下载 Real-ESRGAN + RIFE 的 ncnn-vulkan 二进制与模型
./video2x.sh -h
```

`setup.sh` 会从各自的官方 GitHub Release 获取第三方二进制（**仓库内不打包**），并清除 macOS 隔离属性。

## 图形界面（可选）

内置一个极简的本地网页 GUI——无需上传、原生文件选择、实时进度、三语（EN/中/日）：

```bash
python3 gui.py        # 随后浏览器会打开 http://127.0.0.1:8765
```

或在访达中**双击 `video2x-gui.command`**。底层调用同一个 `video2x.sh`（仅需 Python 3 标准库，无需额外安装）。

## 用法（命令行）

```bash
./video2x.sh -i input.mp4 [-s 2|3|4] [-f N] [-m anime|photo|anime-video] [-x N] [-u on|off] [-r on|off]
```

| 选项 | 含义 | 默认 |
|---|---|---|
| `-i FILE` | 输入视频（**必填**） | — |
| `-s N` | 放大倍率（`2` / `3` / `4`） | `2` |
| `-f N` | 补帧倍率（≥2 的整数；如 24→48fps） | `2` |
| `-m MODEL` | `anime`（x4plus-anime，线条锐利）· `photo`（x4plus）· `anime-video`（animevideov3，偏柔） | `anime` |
| `-x N` | 输出长边上限像素（`0` = 不限制） | `3840`（4K） |
| `-u on\|off` | 开关放大 | `on` |
| `-r on\|off` | 开关补帧 | `on` |

输出文件保存在输入旁边，命名为 `<名称>_v2x.mp4`。

### 示例

```bash
# 放大 ×2 + 补帧 ×2（默认模型，4K 上限）
./video2x.sh -i clip.mp4

# 更锐利的动漫，×2 放大 + 流畅化，上限 5K
./video2x.sh -i clip.mp4 -m anime -s 2 -f 2 -x 5120

# 只补帧（如 30 → 60 fps），不放大
./video2x.sh -i clip.mp4 -u off -r on -f 2
```

## 工作原理

```
输入 → 拆成 PNG 帧 + 提取音频
     → Real-ESRGAN 放大（模型原生倍率）
     → [若超过 -x 上限，或模型仅支持 ×4] lanczos 缩小到目标尺寸（超采样）
     → RIFE 补帧（目标帧数 = 帧数 × 倍率）
     → ffmpeg 以新帧率重新封装 + 原音频
     → 自动删除临时帧 → <名称>_v2x.mp4
```

说明：
- **输出帧率按 实际帧数 ÷ 时长 计算**，而非 `r_frame_rate`，因此**可变帧率（VFR）**素材也能保持音画同步（不会出现“画面全黑、音频继续”）。
- 对仅支持 ×4 的模型（`anime`/`photo`），或当 `-s` 超过 `-x` 上限时，会先放大再缩小——即**超采样**，边缘更干净。
- 尽可能无损复制音频。

## 适配哪些 Mac？

能不能跑门槛很低，差别主要在**速度**（二进制会自动分块以适配显存）：

| 机型 | 可用 | 体感 |
|---|---|---|
| Apple Silicon Pro/Max/Ultra（32GB+） | ✅ | 快 |
| Apple Silicon 标准款（16GB） | ✅ | 可用，较慢 |
| Apple Silicon 标准款（8GB） | ✅* | 分辨率别太高；`-x` 上限有帮助 |
| Intel + Metal GPU | ⚠️ | 经 MoltenVK 可跑，很慢 |

## 致谢与许可

本项目是一个封装层，核心由以下项目完成：
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN)（xinntao）— BSD-3-Clause
- [rife-ncnn-vulkan](https://github.com/nihui/rife-ncnn-vulkan)（nihui）— MIT
- [ncnn](https://github.com/Tencent/ncnn)（腾讯）— BSD-3-Clause
- 灵感来自 [Video2X](https://github.com/k4yt3x/video2x)（k4yt3x）

封装代码：MIT（见 [LICENSE](LICENSE)）。
