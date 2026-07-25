# colibri Portable — Windows GUI Edition

> **Tiny engine, immense model.** Run GLM-5.2 (744B-parameter MoE) on consumer hardware — in pure C, streaming experts from disk.

A portable GUI-enhanced distribution of [colibri](https://github.com/JustVugg/colibri) by [JustVugg](https://github.com/JustVugg). GUI author: **Soror L.'. L.'.** · [Project on GitHub](https://github.com/Methelina/AI_Colibri_GUI_Portable)

[Русская версия](README.ru.md)

---

![GUI window](bin/res/Pintura_001.png)

---

## Quick Start

### 1. Install

```powershell
.\Install_Colibri-UV.ps1
```

Downloads the engine, Python 3.12, and all dependencies into an isolated environment.

### CUDA build (optional, for NVIDIA GPUs)

```powershell
.\build_cuda.ps1
```

The script **auto-detects** CUDA (PATH, CUDA_PATH, Program Files), MinGW gcc (PATH, msys64, mingw64), and MSVC Build Tools (VS2022 standard paths + vswhere). GPU architecture is detected via `nvidia-smi` (RTX 3060 → sm_86, RTX 4090 → sm_89, etc.).

**If a tool is missing** — asks for a manual path with install hints. **If multiple versions found** — lets you pick with `[0] [1] [2]`.

**Prerequisites:**
- [CUDA Toolkit](https://developer.nvidia.com/cuda-downloads) (≥12.0)
- MinGW gcc: via MSYS2 or `scoop install mingw-winlibs`
- [MSVC Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022) with "Desktop development with C++" workload

### 2. Launch

```powershell
.\Run_Colibri.ps1
```

### 3. Model

1. Enter or browse (**+** button) to the model folder
2. Click **Set**
3. If empty — click **Download Model (~370 GB)** (resumable)
4. Green circle = model found

### 4. Run

1. Set toggles (see recommendations below)
2. **Start Serve** → API on port 8000
3. **Start Web UI** → web chat on port 5173
4. In the web UI, press **Probe server**

Or click **Chat** for a console chat window.

---

## Toggle Guide

| Toggle | Recommendation | Description |
|--------|---------------|-------------|
| **CUDA GPU** | ☑ ON with NVIDIA GPU | Enable GPU backend (needs `build_cuda.ps1`) |
| **CUDA Dense** | ☑ ON with CUDA GPU | Dense matmuls on GPU (~10 GB VRAM) |
| **CUDA MTP** | ☐ OFF | MTP under CUDA: fp-divergence kills acceptance |
| **Think block** | ☐ OFF normally | GLM-5.2 reasoning `<think>` block |
| **MTP** | ☑ ON | Multi-Token Prediction: ~2-3x faster on CPU |
| **Pipe I/O** | ☑ ON | Async expert I/O: disk parallel with compute |
| **O_DIRECT** | ☑ ON for NVMe, ☐ OFF for SATA/HDD | Direct disk I/O (+34-65% speedup) |
| **Debug** | ☐ OFF | Raw engine stderr output |
| **KV Save** | ☑ ON | Persist chat context across restarts |
| **Profile** | ☑ ON for benchmarks | Latency percentiles and bottleneck analysis |

### Presets

Three typical configs:

**CPU-only:**
```
MTP ☑  Pipe I/O ☑  O_DIRECT ☑  KV Save ☑  — rest OFF
```

**NVIDIA GPU (12 GB VRAM):**
```
CUDA GPU ☑  CUDA Dense ☑  MTP ☑  Pipe I/O ☑  O_DIRECT ☑  KV Save ☑
CUDA MTP ☐
```

**NVIDIA GPU (24+ GB VRAM):**
```
CUDA GPU ☑  CUDA Dense ☑  MTP ☑  Pipe I/O ☑  O_DIRECT ☑  KV Save ☑
Plus: set CUDA_EXPERT_GB=8 and COLI_CUDA_TC_W4A16=1
```

---

## Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10/11 | Windows 11 24H2 |
| RAM | 16 GB | 48 GB+ |
| Free disk | ~400 GB | NVMe SSD |
| GPU | None required | NVIDIA RTX 3060+ 12 GB VRAM |

## Model

[GLM-5.2 int4 with int8 MTP heads](https://huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp) (~370 GB). Built-in resumable downloader in the GUI.

## Links

- **Original project**: [github.com/JustVugg/colibri](https://github.com/JustVugg/colibri)
- **Our portable GUI**: [github.com/Methelina/AI_Colibri_GUI_Portable](https://github.com/Methelina/AI_Colibri_GUI_Portable)
- **Model**: [huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp](https://huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp)

## License

Original colibri engine — MIT, see [LICENSE](LICENSE). GUI wrapper and installer — same license.
