"""
colibri GUI — DearPyGui control panel for the colibri engine.
Start/stop serve, launch chat, run one-shot, monitor GPU/RAM.
Based on KimoDer pattern by Soror L.'. L.'.
"""

import json, os, queue, re, subprocess, sys, textwrap, threading, time, webbrowser
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import colibri_ctl as cc
import dearpygui.dearpygui as dpg

# ── Tag constants ──
SC = "status_circle";  ST = "status_text"
SSC = "serve_circle";  SST = "serve_text";  SPT = "serve_port_text"
WSC = "web_circle";  WST = "web_text";  WPT = "web_port_text"
MC = "model_path_text"; ET = "engine_path_text"
VT = "vram_text";      RT = "ram_text"
LG = "log_area";       CK = "autoscroll_cb"
SH = "sect_engine";    DH = "sect_serve"
GL = "gpu_label";      RL = "ram_label"

# ── State ──
_q = queue.Queue()
_sd = threading.Event()
_logbuf = []
LB = 8000
_wrap_cache = {"chars": 0}

_presets = {}
_presets_file = Path(__file__).resolve().parent.parent / "colibri_presets.json"
_env_keys = [
    "COLI_MODEL", "SNAP", "RAM_GB", "CTX", "NGEN",
    "COLI_TEMP", "TOPK", "TOPP", "NUCLEUS", "SEED",
    "KVSAVE", "KV_SLOTS", "THINK", "MTP", "DRAFT", "SPEC",
    "PIPE", "PIPE_WORKERS", "DIRECT", "MLOCK", "CAP_RAISE",
    "COLI_CUDA", "COLI_GPU", "CUDA_DENSE", "CUDA_EXPERT_GB",
    "COLI_CUDA_PIPE", "COLI_CUDA_MTP", "COLI_CUDA_TC_W4A16",
    "COLI_METAL", "COLI_POLICY", "COLI_API_KEY", "COLI_DEBUG",
    "COLI_TOOL_SALVAGE", "COLI_THINK", "CHAT_TEMPLATE",
    "PROF", "PILOT", "PILOT_REAL", "AUTOPIN", "PIN", "PIN_GB",
    "CACHE_ROUTE", "COLI_NUMA", "COLI_NO_OMP_TUNE",
]


def _strip_ansi(text):
    """Remove ANSI escape codes so DearPyGui text widget renders cleanly."""
    return re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', text)


def ct(tag, msg):
    """Thread-safe log — matches KimoDer EveryNyan pattern."""
    msg = _strip_ansi(msg)
    u = msg.upper()
    sym = " "
    if any(w in u for w in ("ERROR", "TRACEBACK", "FAIL")): sym = "!"
    elif "WARN" in u: sym = "*"
    elif "READY" in u or "loaded" in msg: sym = "+"
    elif ">>>" in msg[:4] or "Starting" in msg: sym = ">"
    elif "STATUS" in u[:10]: sym = "."
    line = f"[{tag.center(18)}] {sym} {msg}"
    print(line, flush=True)
    _q.put(("log", line))


def load_presets():
    global _presets
    if _presets_file.is_file():
        try:
            _presets = json.loads(_presets_file.read_text(encoding="utf-8"))
        except Exception:
            _presets = {}


def save_presets_to_disk():
    try:
        _presets_file.write_text(json.dumps(_presets, indent=2, ensure_ascii=False), encoding="utf-8")
    except Exception:
        pass


def _engine_state():
    e = cc.find_engine()
    m = cc.find_model_path()
    coli = cc.find_coli()
    if not e: return (110, 110, 110), "NO ENGINE", "colibri.exe not found"
    if not coli: return (240, 200, 60), "NO COLI", "coli launcher not found"
    if not m: return (240, 200, 60), "NO MODEL", "model path not set"
    running, pid, port = cc.serve_status()
    if running: return (80, 210, 100), "SERVING", f"pid {pid} :{port}"
    return (80, 210, 100), "READY", "engine + model OK"


def _serve_state():
    running, pid, port = cc.serve_status()
    if running:
        return (80, 210, 100), "RUNNING", f"port :{port}  pid {pid}"
    return (110, 110, 110), "STOPPED", ""


def _web_state():
    running, pid, port = cc.web_status()
    if running:
        return (80, 210, 100), "RUNNING", f"port :{port}  pid {pid}"
    web_dir = cc.find_web_dir()
    if not web_dir or not (web_dir / "node_modules").is_dir():
        return (240, 200, 60), "NO DEPS", "run npm install"
    return (110, 110, 110), "STOPPED", ""


def apply_ui():
    ec, el, ed = _engine_state()
    if dpg.does_item_exist(SC):
        dpg.configure_item(SC, fill=ec)
        dpg.set_value(ST, el); dpg.configure_item(ST, color=ec)
        dpg.set_value(ET, ed)

    sc, sl, sd = _serve_state()
    if dpg.does_item_exist(SSC):
        dpg.configure_item(SSC, fill=sc)
        dpg.set_value(SST, sl); dpg.configure_item(SST, color=sc)
        dpg.set_value(SPT, sd)
        dpg.configure_item("btn_stop_serve", enabled=(sl == "RUNNING"))
        dpg.configure_item("btn_start_serve", enabled=(sl != "RUNNING"))
        dpg.configure_item("btn_open_serve", enabled=(sl == "RUNNING"))

    wc, wl, wd = _web_state()
    if dpg.does_item_exist(WSC):
        dpg.configure_item(WSC, fill=wc)
        dpg.set_value(WST, wl); dpg.configure_item(WST, color=wc)
        dpg.set_value(WPT, wd)
        dpg.configure_item("btn_stop_web", enabled=(wl == "RUNNING"))
        dpg.configure_item("btn_start_web", enabled=(wl != "RUNNING"))
        dpg.configure_item("btn_open_web", enabled=(wl == "RUNNING"))

    model = cc.find_model_path() or "(not set)"
    if dpg.does_item_exist(MC): dpg.set_value(MC, model)

    has_model = bool(cc.find_model_path())
    if dpg.does_item_exist("dl_section"):
        dpg.configure_item("dl_section", show=not has_model)

    if dpg.does_item_exist(VT): dpg.set_value(VT, cc.vram_snapshot())
    if dpg.does_item_exist(RT): dpg.set_value(RT, cc.ram_snapshot())


def _render_log(force=False):
    if not dpg.does_item_exist(LG): return
    try: w = dpg.get_item_rect_size(LG)[0]
    except: return
    chars = max(40, int((w - 40) / 7))
    if not force and chars == _wrap_cache["chars"]: return
    _wrap_cache["chars"] = chars
    out = []
    for line in _logbuf:
        out.extend(textwrap.wrap(line, width=chars, replace_whitespace=False, drop_whitespace=False) or [""])
    if len(out) > 800: out = out[-800:]
    dpg.set_value(LG, "\n".join(out))


def dq():
    for _ in range(200):
        try: k, p = _q.get_nowait()
        except: break
        if k == "log":
            _logbuf.append(p)
            if len(_logbuf) > 400: del _logbuf[:200]
            _render_log(force=True)
    if dpg.does_item_exist(CK) and dpg.does_item_exist(LG):
        dpg.configure_item(LG, tracked=dpg.get_value(CK))


def tail_log(log_path_fn, tag):
    off = 0; first = True
    lp = log_path_fn()
    while not _sd.is_set():
        try:
            if lp.is_file():
                sz = lp.stat().st_size
                if first: off = sz; first = False
                if sz < off: off = sz
                if sz > off:
                    with open(lp, "r", encoding="utf-8", errors="replace") as f:
                        f.seek(off); chunk = f.read()
                    off = lp.stat().st_size
                    for ln in chunk.splitlines():
                        ln = ln.strip('\x00').rstrip()
                        if ln: ct(tag, ln)
            else:
                first = True
        except Exception: pass
        _sd.wait(0.5)


def monitor():
    while not _sd.is_set():
        apply_ui()
        _sd.wait(1.0)


def monitor_hw():
    while not _sd.is_set():
        try:
            val = cc.vram_snapshot()
            if val and dpg.does_item_exist(VT): dpg.set_value(VT, val)
        except: pass
        try:
            val = cc.ram_snapshot()
            if val and dpg.does_item_exist(RT): dpg.set_value(RT, val)
        except: pass
        _sd.wait(3.0)


# ── Button actions ──
def act_serve_start():
    def w():
        ct("GUI", ">>> starting serve ...")
        cc.start_serve(status_cb=lambda m: ct("GUI", f"SERVE: {m}"))
    threading.Thread(target=w, daemon=True).start()


def act_serve_stop():
    def w():
        ct("GUI", ">>> stopping serve ...")
        cc.stop_serve(status_cb=lambda m: ct("GUI", f"SERVE: {m}"))
    threading.Thread(target=w, daemon=True).start()


def act_serve_open():
    _, _, port = cc.serve_status()
    if port:
        import urllib.request
        try: urllib.request.urlopen(f"http://127.0.0.1:{port}", timeout=2)
        except: pass
        webbrowser.open(f"http://127.0.0.1:{port}/docs")


def act_web_start():
    port_text = dpg.get_value("web_port_input").strip()
    try: port = int(port_text)
    except: port = 8393

    def w():
        ct("GUI", f">>> starting Web UI on :{port} ...")
        cc.start_web(port=port, status_cb=lambda m: ct("GUI", f"WEB: {m}"))
    threading.Thread(target=w, daemon=True).start()


def act_web_stop():
    def w():
        ct("GUI", ">>> stopping Web UI ...")
        cc.stop_web(status_cb=lambda m: ct("GUI", f"WEB: {m}"))
    threading.Thread(target=w, daemon=True).start()


def act_web_open():
    _, _, port = cc.web_status()
    if port: webbrowser.open(f"http://127.0.0.1:{port}")


def act_chat():
    def w():
        ct("GUI", ">>> launching chat (new console) ...")
        cc.start_chat(status_cb=lambda m: ct("GUI", f"CHAT: {m}"))
    threading.Thread(target=w, daemon=True).start()


def act_run():
    prompt = dpg.get_value("run_prompt_input")
    if not prompt.strip():
        ct("GUI", "! Prompt is empty")
        return
    def w():
        ct("GUI", f">>> run: {prompt[:60]}...")
        rc, out = cc.run_oneshot(prompt, ngen=256, status_cb=lambda m: ct("GUI", f"RUN: {m}"))
        ct("GUI", f">>> run finished (rc={rc})")
        if out:
            for ln in out.strip().splitlines():
                ct("RUN", ln)
    threading.Thread(target=w, daemon=True).start()


def act_doctor():
    def w():
        ct("GUI", ">>> doctor ...")
        rc, out = cc.run_doctor(status_cb=lambda m: ct("GUI", f"DOC: {m}"))
        if out:
            for ln in out.strip().splitlines():
                ct("DOCTOR", ln)
    threading.Thread(target=w, daemon=True).start()


def act_plan():
    def w():
        ct("GUI", ">>> plan ...")
        rc, out = cc.run_plan(status_cb=lambda m: ct("GUI", f"PLAN: {m}"))
        if out:
            for ln in out.strip().splitlines():
                ct("PLAN", ln)
    threading.Thread(target=w, daemon=True).start()


def act_log_folder():
    try: os.startfile(str(cc.runtime_dir()))
    except: pass


def act_download_model():
    dest = dpg.get_value("dl_folder_input").strip()
    if not dest:
        ct("GUI", "! Enter a target folder for the model")
        return
    def w():
        ct("GUI", f">>> Downloading model to {dest} (~{cc.MODEL_SIZE_GB} GB, resumable)...")
        cc.start_model_download(dest, status_cb=lambda m: ct("GUI", f"DL: {m}"))
        # Refresh model path after download
        if dpg.does_item_exist(MC):
            dpg.set_value(MC, cc.find_model_path() or dest)
    threading.Thread(target=w, daemon=True).start()


def act_preset_save():
    name = dpg.get_value("preset_name_input").strip()
    if not name:
        ct("GUI", "! Preset name is empty")
        return
    vals = {}
    for k in _env_keys:
        v = os.environ.get(k, "")
        if v: vals[k] = v
    _presets[name] = vals
    save_presets_to_disk()
    ct("GUI", f"+ Preset '{name}' saved")
    refresh_preset_list()


def act_preset_load():
    name = dpg.get_value("preset_name_input").strip()
    if not name or name not in _presets:
        ct("GUI", f"! Preset '{name}' not found")
        return
    for k, v in _presets[name].items():
        os.environ[k] = str(v)
    ct("GUI", f"+ Preset '{name}' loaded ({len(_presets[name])} vars)")


def refresh_preset_list():
    if dpg.does_item_exist("preset_list"):
        names = ", ".join(sorted(_presets.keys())) or "(none)"
        dpg.set_value("preset_list", f"Presets: {names}")


# ── Env quick toggles (checkbox-driven) ──
_env_toggles = [
    ("COLI_CUDA",    "CUDA GPU",    "0", "Enable NVIDIA GPU backend (needs coli_cuda.dll)"),
    ("CUDA_DENSE",   "CUDA Dense",  "0", "Place dense matmuls on GPU (~10 GB VRAM required)"),
    ("COLI_CUDA_MTP","CUDA MTP",    "0", "MTP speculation under CUDA (off: fp-divergence on int4)"),
    ("THINK",        "Think block", "0", "GLM-5.2 reasoning <think> block in output"),
    ("MTP",          "MTP",         "1", "Multi-Token Prediction — 2-3x faster (CPU path)"),
    ("PIPE",         "Pipe I/O",    "0", "Overlap disk-load with matmul via async threads"),
    ("DIRECT",       "O_DIRECT",    "0", "Unbuffered disk reads (+34-65% on NVMe, measure first)"),
    ("COLI_DEBUG",   "Debug",       "0", "Tee engine I/O to stderr (1=output, 2=prompt+output)"),
    ("KVSAVE",       "KV Save",     "1", "Persist chat KV-cache to disk (warm reopen)"),
    ("PROF",         "Profile",     "0", "Performance profile: latency %, bottleneck verdict"),
]

_env_toggle_tags = []


def _on_env_toggle(sender, app_data, user_data):
    key = user_data
    val = "1" if app_data else "0"
    os.environ[key] = val
    ct("GUI", f". env {key}={val}")


def _sync_env_toggles():
    for key, _, default, *rest in _env_toggles:
        tag = f"env_toggle_{key}"
        if dpg.does_item_exist(tag):
            cur = os.environ.get(key, default)
            dpg.set_value(tag, cur == "1" or cur.lower() == "true")


# ── GUI build ──
def build_gui():
    with dpg.theme() as gt:
        with dpg.theme_component(dpg.mvAll):
            dpg.add_theme_color(dpg.mvThemeCol_WindowBg, (25, 25, 35))
            dpg.add_theme_color(dpg.mvThemeCol_ChildBg, (20, 22, 26))
            dpg.add_theme_color(dpg.mvThemeCol_Button, (45, 55, 70))
            dpg.add_theme_color(dpg.mvThemeCol_ButtonHovered, (65, 80, 100))
            dpg.add_theme_color(dpg.mvThemeCol_ButtonActive, (85, 100, 120))
            dpg.add_theme_color(dpg.mvThemeCol_FrameBg, (40, 42, 50))
            dpg.add_theme_color(dpg.mvThemeCol_Text, (220, 220, 220))
            dpg.add_theme_style(dpg.mvStyleVar_FrameRounding, 4)
            dpg.add_theme_style(dpg.mvStyleVar_WindowRounding, 6)
    dpg.bind_theme(gt)

    with dpg.theme() as serve_green:
        with dpg.theme_component(dpg.mvButton):
            dpg.add_theme_color(dpg.mvThemeCol_Button, (45, 55, 70))
            dpg.add_theme_color(dpg.mvThemeCol_Text, (80, 210, 100))
    with dpg.theme() as serve_dim:
        with dpg.theme_component(dpg.mvButton):
            dpg.add_theme_color(dpg.mvThemeCol_Button, (30, 38, 50))
            dpg.add_theme_color(dpg.mvThemeCol_Text, (140, 145, 155))

    fonts_ok = False
    try:
        font_dir = cc.repo_root() / "bin" / "res"
        reg = font_dir / "ModeSevenBETAVHS.ttf"
        caps = font_dir / "ModeSevenBETAVHS20212.ttf"
        if reg.is_file() and caps.is_file():
            with dpg.font_registry():
                with dpg.font(str(reg), 16, tag="font_regular"):
                    pass
                with dpg.font(str(caps), 16, tag="font_caps"):
                    pass
            dpg.bind_font("font_regular")
            fonts_ok = True
    except Exception: pass

    with dpg.window(tag="main_window", label="colibri Control", autosize=True,
                    no_resize=False, no_collapse=True):
        # ── Header ──
        with dpg.group(horizontal=True):
            dpg.add_text("colibri v1.1", tag="ver_text", color=(255, 200, 100))
            dpg.add_text("  |  GLM-5.2 · MoE Streaming", color=(140, 145, 155))
            dpg.add_text("    ")
            dpg.add_text("GPU", tag=GL, color=(255, 200, 100))
            dpg.add_text("<0%> VRAM: 0/0Gb", tag=VT, color=(180, 185, 195))
            dpg.add_text(" || ", color=(140, 145, 155))
            dpg.add_text("RAM", tag=RL, color=(255, 200, 100))
            dpg.add_text("<0%> 0/0Gb", tag=RT, color=(180, 185, 195))
        dpg.add_separator()

        # ── Engine status ──
        dpg.add_spacer(height=4)
        with dpg.group(horizontal=True):
            with dpg.drawlist(width=20, height=20):
                dpg.draw_circle(center=(10, 10), radius=7, tag=SC, fill=(110, 110, 110))
            dpg.add_text("Engine", tag=SH, color=(255, 200, 100))
            dpg.add_text("  ")
            dpg.add_text("CHECKING", tag=ST, color=(110, 110, 110))
        dpg.add_text("", tag=ET, color=(160, 165, 175), indent=24)
        dpg.add_text("model:", tag=MC, color=(160, 165, 175), indent=24)
        if not cc.engine_has_cuda():
            dpg.add_text("GPU: CPU-ONLY — rebuild: .\\build_cuda.ps1", tag="cuda_warn",
                         color=(240, 180, 60), indent=24)
        dpg.add_spacer(height=2)

        # ── Model download (visible only when model not found) ──
        with dpg.group(tag="dl_section", show=False):
            dpg.add_text("Model not found — download required", tag="dl_title", color=(255, 160, 60))
            repo_alive = cc.check_repo_alive()
            repo_status = "HF repo reachable" if repo_alive else "HF repo UNREACHABLE (check internet)"
            repo_color = (80, 210, 100) if repo_alive else (230, 70, 70)
            dpg.add_text(repo_status, tag="dl_repo_status", color=repo_color)
            dpg.add_text("Repo: mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp", tag="dl_repo",
                         color=(140, 145, 155), indent=4)
            dpg.add_text("Size: ~370 GB — resumable download", tag="dl_size",
                         color=(140, 145, 155), indent=4)
            with dpg.group(horizontal=True):
                dpg.add_input_text(tag="dl_folder_input", width=-120,
                                   default_value=cc.default_model_dir(), hint="target folder")
                dpg.add_button(label="Download Model", callback=act_download_model)
            with dpg.tooltip(dpg.last_item()):
                dpg.add_text("Start resumable download via pycurl + HF API")
                dpg.add_text("Safe to interrupt — re-run to continue from where it stopped")
            dpg.add_spacer(height=4)

        with dpg.group(indent=24):
            dpg.add_button(label="Chat (new console)", callback=act_chat)
            with dpg.tooltip(dpg.last_item()):
                dpg.add_text("Open interactive colibri chat in a new console")
                dpg.add_text("Chat remembers context between sessions (KV cache)")
            with dpg.group(horizontal=True):
                dpg.add_input_text(tag="run_prompt_input", width=-120, hint="Prompt text...",
                                   on_enter=True, callback=act_run)
                dpg.add_button(label="Run", callback=act_run)
            with dpg.tooltip(dpg.last_item()):
                dpg.add_text("One-shot generation with the prompt above")
                dpg.add_text("Type in the field, press Run or Enter")
            dpg.add_button(label="Doctor (check)", callback=act_doctor)
            with dpg.tooltip(dpg.last_item()):
                dpg.add_text("Run coli doctor — checks engine, model, compiler")
                dpg.add_text("Useful before first run or when something breaks")
            dpg.add_button(label="Plan (resource)", callback=act_plan)
            with dpg.tooltip(dpg.last_item()):
                dpg.add_text("Run coli plan — shows RAM/VRAM placement for this model")
                dpg.add_text("Reports how experts will be split across RAM, VRAM, disk")
        dpg.add_separator()

        # ── Serve ──
        dpg.add_spacer(height=4)
        with dpg.group(horizontal=True):
            with dpg.drawlist(width=20, height=20):
                dpg.draw_circle(center=(10, 10), radius=7, tag=SSC, fill=(110, 110, 110))
            dpg.add_text("API Server", tag=DH, color=(255, 200, 100))
            dpg.add_text("", tag=SPT, color=(255, 200, 100))
            dpg.add_text("  ")
            dpg.add_text("STOPPED", tag=SST, color=(110, 110, 110))
        dpg.add_spacer(height=2)
        with dpg.group(indent=24):
            dpg.add_button(label="Start Serve", tag="btn_start_serve", callback=act_serve_start)
            with dpg.tooltip(dpg.last_item()):
                dpg.add_text("Start OpenAI-compatible API server on port 8000")
                dpg.add_text("Works with ChatGPT clients, OpenCode, Claude Code, etc.")
            dpg.add_button(label="Open API docs", tag="btn_open_serve", enabled=False, callback=act_serve_open)
            dpg.bind_item_theme("btn_open_serve", "serve_dim")
            with dpg.tooltip("btn_open_serve"):
                dpg.add_text("Open /docs Swagger UI in browser")
                dpg.add_text("Shows all API endpoints: /v1/chat/completions, /v1/models, etc.")
            dpg.add_button(label="Stop Serve", tag="btn_stop_serve", enabled=False, callback=act_serve_stop)
            with dpg.tooltip(dpg.last_item()):
                dpg.add_text("Stop the API server and free the port")
            dpg.add_button(label="Log Folder", callback=act_log_folder)
            with dpg.tooltip(dpg.last_item()):
                dpg.add_text("Open runtime log folder in Explorer")
        dpg.add_separator()

        # ── Web UI ──
        dpg.add_spacer(height=4)
        with dpg.group(horizontal=True):
            with dpg.drawlist(width=20, height=20):
                dpg.draw_circle(center=(10, 10), radius=7, tag=WSC, fill=(110, 110, 110))
            dpg.add_text("Web Chat UI  (React/Vite)", tag="sect_web", color=(255, 200, 100))
            dpg.add_text("", tag=WPT, color=(255, 200, 100))
            dpg.add_text("  ")
            dpg.add_text("STOPPED", tag=WST, color=(110, 110, 110))
        dpg.add_spacer(height=2)
        with dpg.group(indent=24):
            with dpg.group(horizontal=True):
                dpg.add_input_text(tag="web_port_input", width=60, default_value="8393", hint="port")
                dpg.add_button(label="Start Web UI", tag="btn_start_web", callback=act_web_start)
            with dpg.tooltip("btn_start_web"):
                dpg.add_text("Start React/Vite web chat interface")
                dpg.add_text("Uses the port shown in the field (default 8393)")
            dpg.add_button(label="Open Web UI", tag="btn_open_web", enabled=False, callback=act_web_open)
            dpg.bind_item_theme("btn_open_web", "serve_dim")
            with dpg.tooltip("btn_open_web"):
                dpg.add_text("Open web chat in browser")
                dpg.add_text("Press Probe server in the UI to connect to :8000 API")
            dpg.add_button(label="Stop Web UI", tag="btn_stop_web", enabled=False, callback=act_web_stop)
            with dpg.tooltip("btn_stop_web"):
                dpg.add_text("Stop the web chat interface")
        dpg.add_separator()

        # ── Env quick toggles ──
        dpg.add_spacer(height=4)
        dpg.add_text("Quick Toggles", color=(255, 200, 100))
        row_size = 5
        for row_start in range(0, len(_env_toggles), row_size):
            row_items = _env_toggles[row_start:row_start + row_size]
            with dpg.group(horizontal=True):
                for item in row_items:
                    key, label, default, *desc = item
                    tag = f"env_toggle_{key}"
                    _env_toggle_tags.append(tag)
                    init_val = os.environ.get(key, default) in ("1", "true", "True")
                    dpg.add_checkbox(label=label, tag=tag, default_value=init_val,
                                     callback=_on_env_toggle, user_data=key)
                    if desc:
                        with dpg.tooltip(tag):
                            dpg.add_text(desc[0])
        dpg.add_separator()

        # ── Presets ──
        dpg.add_spacer(height=4)
        with dpg.group(horizontal=True):
            dpg.add_input_text(tag="preset_name_input", width=150, hint="preset name")
            dpg.add_button(label="Save", callback=act_preset_save)
            dpg.add_button(label="Load", callback=act_preset_load)
        dpg.add_text("Presets: (none)", tag="preset_list", color=(140, 145, 155))
        with dpg.tooltip("preset_list"):
            dpg.add_text("Save/load full environment config as named preset")
            dpg.add_text("Stored in colibri_presets.json")
        dpg.add_separator()

        # ── Log ──
        dpg.add_checkbox(label="Auto-scroll", tag=CK, default_value=True)
        dpg.add_input_text(tag=LG, multiline=True, readonly=True, width=-1, height=-1, tracked=True)

    dpg.create_viewport(title="colibri — GLM-5.2 Control", width=720, height=700)
    if fonts_ok:
        for t in (SH, DH, "sect_web", "ver_text"): dpg.bind_item_font(t, "font_caps")
    dpg.setup_dearpygui(); dpg.show_viewport(); dpg.set_primary_window("main_window", True)


def cleanup():
    global _sd
    _sd.set()
    ct("GUI", "Shutting down colibri environment...")
    try: cc.stop_serve(status_cb=lambda m: ct("GUI", f"{m}"))
    except: pass
    try: cc.stop_web(status_cb=lambda m: ct("GUI", f"{m}"))
    except: pass
    try: cc.cleanup_env_processes(status_cb=lambda m: ct("GUI", f"{m}"))
    except: pass


def main():
    try:
        return _main()
    except Exception:
        import traceback
        traceback.print_exc()
        return 1


def _main():
    dpg.create_context()
    try:
        return _run()
    finally:
        dpg.destroy_context()


def _run():
    if not cc.is_installed():
        ct("GUI", "Environment not installed. Run Install_Colibri-UV.ps1 first.")
        return 1
    ct("GUI", "colibri GUI starting...")
    ct("GUI", f"Repo root: {cc.repo_root()}")
    ct("GUI", f"Engine: {cc.find_engine() or 'NOT FOUND'}")
    ct("GUI", f"Model: {cc.find_model_path() or 'NOT SET'}")

    load_presets()
    _sync_env_toggles()

    try: cc.log_path().write_text("", encoding="utf-8")
    except: pass

    build_gui()
    refresh_preset_list()

    for w in [threading.Thread(target=tail_log, args=(cc.log_path, "SERVE"), daemon=True),
              threading.Thread(target=tail_log, args=(cc.web_log_path, "WEB UI"), daemon=True),
              threading.Thread(target=monitor, daemon=True),
              threading.Thread(target=monitor_hw, daemon=True)]:
        w.start()

    while dpg.is_dearpygui_running():
        try:
            dq(); _render_log(); _sync_env_toggles()
            dpg.render_dearpygui_frame()
        except Exception as e:
            ct("GUI", f"Render error: {e}")
            break

    cleanup()
    return 0


if __name__ == "__main__":
    sys.exit(main())
