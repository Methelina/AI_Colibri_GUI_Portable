# colibri Portable — Windows GUI Edition

**Tiny engine, immense model.** Run GLM-5.2 (744B-parameter Mixture-of-Experts) on consumer hardware — in pure C, streaming experts from disk.

This is a portable, GUI-enhanced distribution of the original [colibri](https://github.com/JustVugg/colibri) project by [JustVugg](https://github.com/JustVugg). All credit for the engine and model pipeline belongs to the original authors.

---

## What we added

| Feature | Description |
|---------|-------------|
| **DearPyGui control panel** | Start/stop server, launch chat, run prompts, monitor GPU/RAM — all from a graphical interface |
| **One-click installer** | `Install_Colibri-UV.ps1` sets up everything: downloads engine, creates isolated Python 3.12 environment, installs Web UI dependencies |
| **CUDA build script** | `build_cuda.ps1` rebuilds the engine with NVIDIA GPU support (RTX 3060 tested) |
| **Model downloader** | Built-in pycurl-based HF downloader with resume support (~370 GB model) |
| **Web chat interface** | React/Vite dashboard connecting to the local API server |
| **Environmental presets** | Save/load full configurations (CUDA flags, generation params, I/O tuning) |
| **ModeSeven fonts** | Bitmap terminal aesthetic with Cyrillic support |

## Quick Start

```powershell
# 1. Install the portable environment
.\Install_Colibri-UV.ps1

# 2. Launch the GUI
.\Run_Colibri.ps1

# 3. Use the GUI to:
#    - Download the model (if not already present)
#    - Start the API server on port 8000
#    - Open web chat at http://127.0.0.1:8393
```

### CLI shortcuts (no GUI)

```powershell
.\Run_Colibri.ps1 -Serve          # Start API server
.\Run_Colibri.ps1 -StopServe      # Stop API server
.\Run_Colibri.ps1 -Doctor         # Health check
.\Run_Colibri.ps1 -Plan           # Resource plan
```

### GPU (CUDA) support

The installer downloads a **CPU-only** binary. For NVIDIA GPU acceleration:

```powershell
.\build_cuda.ps1                  # Rebuild with sm_86 (RTX 3060)
```

Then enable **CUDA GPU** and **CUDA Dense** toggles in the GUI.

## Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10/11 | Windows 11 24H2 |
| RAM | 16 GB | 48 GB+ |
| Free disk | ~400 GB NVMe SSD | Two NVMe SSDs (model mirror) |
| GPU | None required | NVIDIA RTX 3060+ 12 GB VRAM |
| Python | 3.12 (auto-installed) | — |
| Node.js | For Web UI | 18+ |

## Model

The recommended model is [GLM-5.2 int4 with int8 MTP heads](https://huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp) (~370 GB).

The GUI includes a built-in downloader (resumable, via pycurl). If the model is not found on startup, a download section appears automatically with folder selection and progress in the log.

## Project layout

```
colibri.exe                # C engine (pre-built or CUDA-rebuilt)
coli                       # Python CLI launcher
colibri_env/               # Isolated Python 3.12 (auto-created)
scripts/
├── colibri_gui.py         # DearPyGui control panel
├── colibri_ctl.py         # Process management module
└── _hf_pycurl_download.py # HF model downloader
bin/res/                   # Fonts, resources
src/colibri/               # Original colibri source (reference)
```

## Links

- **Original project**: [github.com/JustVugg/colibri](https://github.com/JustVugg/colibri)
- **Website**: [justvugg.github.io/colibri](https://justvugg.github.io/colibri)
- **Releases**: [github.com/JustVugg/colibri/releases](https://github.com/JustVugg/colibri/releases)
- **Model**: [huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp](https://huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp)

## License

The original colibri engine is licensed under MIT — see [LICENSE](LICENSE) and the [original repository](https://github.com/JustVugg/colibri). The GUI wrapper and portable installer scripts follow the same license.
