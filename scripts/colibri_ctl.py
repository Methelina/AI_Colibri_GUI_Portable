"""
colibri control module — start/stop/monitor for colibri.exe + coli.
Imported by colibri_gui.py; also usable as CLI: python colibri_ctl.py serve|stop|health|run
"""

import os, re, socket, subprocess, sys, time
from pathlib import Path


HOST = "127.0.0.1"
DEFAULT_SERVE_PORT = 8000

_smi_cache = {"time": 0, "value": ""}
_mem_cache = {"time": 0, "value": ""}


def hidden_flags() -> int:
    if os.name != "nt": return 0
    return subprocess.CREATE_NO_WINDOW


def detached_flags() -> int:
    if os.name != "nt": return 0
    return subprocess.CREATE_NO_WINDOW | subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def python_exe() -> Path | None:
    root = repo_root()
    for c in (root / "colibri_env" / "Scripts" / "python.exe",
              root / "colibri_env" / "python.exe"):
        if c.is_file(): return c
    return None


def is_installed() -> bool:
    return python_exe() is not None


def runtime_dir() -> Path:
    t = os.environ.get("TEMP") or str(Path.home())
    p = Path(t) / "colibri-runtime"
    p.mkdir(parents=True, exist_ok=True)
    return p


def log_path() -> Path:
    return runtime_dir() / "colibri-serve.log"


def pid_path() -> Path:
    return runtime_dir() / "colibri-serve.pid"


def find_engine() -> Path | None:
    root = repo_root()
    for p in (root / "colibri.exe",
              root / "src" / "colibri" / "c" / "colibri.exe"):
        if p.is_file(): return p
    return None


def find_coli() -> Path | None:
    root = repo_root()
    for p in (root / "coli",
              root / "src" / "colibri" / "c" / "coli"):
        if p.is_file(): return p
    return None


def find_model_path() -> str:
    env = os.environ.get("COLI_MODEL") or os.environ.get("SNAP") or ""
    if env and Path(env).is_dir(): return env
    for guess in (r"K:\work\AI\local_AI_Models\GLM_52",
                  r"D:\glm52_i4",
                  r"E:\glm52_i4"):
        if Path(guess).is_dir(): return guess
    return ""


MODEL_REPO = "mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp"
MODEL_SIZE_GB = 370


def find_downloader() -> Path | None:
    for p in (repo_root() / "scripts" / "_hf_pycurl_download.py",
              repo_root() / "_hf_pycurl_download.py"):
        if p.is_file(): return p
    return None


def default_model_dir() -> str:
    guesses = [r"K:\work\AI\local_AI_Models\GLM_52",
               r"D:\glm52_i4",
               r"E:\glm52_i4"]
    for g in guesses:
        if Path(g).is_dir(): return g
    # Return first guess as suggested default even if doesn't exist yet
    return guesses[0]


def check_repo_alive(repo: str = MODEL_REPO) -> bool:
    """Quick check if HF repo is accessible via Tree API."""
    import urllib.request, json
    endpoint = os.environ.get("HF_ENDPOINT", "https://huggingface.co").rstrip("/")
    url = f"{endpoint}/api/models/{repo}/tree/main?recursive=0"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "colibri-gui/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            return isinstance(data, list) and len(data) > 0
    except Exception:
        return False


def start_model_download(dest_dir: str, repo: str = MODEL_REPO,
                         status_cb=None) -> int:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    downloader = find_downloader()
    py = python_exe() or sys.executable

    if not downloader:
        emit("Downloader script not found (scripts/_hf_pycurl_download.py)")
        return 1

    Path(dest_dir).mkdir(parents=True, exist_ok=True)

    emit(f"Downloading {repo} → {dest_dir} (~{MODEL_SIZE_GB} GB)")
    emit(f"Resumable: re-run to continue if interrupted")
    try:
        proc = subprocess.Popen(
            [py, str(downloader), repo, dest_dir, "--revision", "main", "--repo-type", "model"],
            cwd=str(repo_root()),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            creationflags=hidden_flags())
        for line in proc.stdout:
            line = line.rstrip()
            if line: emit(line)
        proc.wait()
        if proc.returncode == 0:
            emit(f"Download complete: {dest_dir}")
            os.environ["COLI_MODEL"] = dest_dir
            os.environ["SNAP"] = dest_dir
            return 0
        else:
            emit(f"Download FAILED (exit {proc.returncode})")
            return 1
    except Exception as e:
        emit(f"Download error: {e}")
        return 1


def find_cuda_dll() -> Path | None:
    engine = find_engine()
    if not engine: return None
    dll = engine.with_name("coli_cuda.dll")
    if dll.is_file(): return dll
    alt = repo_root() / "coli_cuda.dll"
    if alt.is_file(): return alt
    return None


def engine_has_cuda() -> bool:
    return find_cuda_dll() is not None


def build_script_path() -> Path:
    return repo_root() / "build_cuda.ps1"
    env = dict(os.environ)
    rt = runtime_dir()
    env["PYTHONUNBUFFERED"] = "1"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    root = repo_root()
    cache = root / ".cache"
    env["HF_HOME"] = str(cache / "huggingface")
    env["PIP_CACHE_DIR"] = str(cache / "pip")
    if model_path:
        env["COLI_MODEL"] = str(model_path)
        env["SNAP"] = str(model_path)
    return env


def vram_snapshot() -> str:
    global _smi_cache
    if os.name != "nt": return ""
    now = time.time()
    if now - _smi_cache["time"] < 3.0: return _smi_cache["value"]
    try:
        o = subprocess.run(["nvidia-smi", "--query-gpu=memory.used,memory.total,utilization.gpu",
                            "--format=csv,noheader,nounits"], capture_output=True, text=True,
                           timeout=5, creationflags=hidden_flags())
        if o.returncode == 0 and o.stdout.strip():
            parts = [x.strip() for x in o.stdout.strip().split(",")[0:3]]
            u, t, ut = int(parts[0]) // 1024, int(parts[1]) // 1024, parts[2]
            val = f"<{ut}%> VRAM: {u}/{t}Gb"
            _smi_cache = {"time": now, "value": val}
            return val
    except Exception: pass
    return _smi_cache["value"]


def ram_snapshot() -> str:
    global _mem_cache
    now = time.time()
    if now - _mem_cache["time"] < 3.0: return _mem_cache["value"]
    try:
        import psutil
        vm = psutil.virtual_memory()
        val = f"<{vm.percent}%> {vm.used/(1024**3):.1f}/{vm.total/(1024**3):.1f}Gb"
        _mem_cache["time"] = now
        _mem_cache["value"] = val
        return val
    except Exception: return _mem_cache["value"]


def pid_alive(pid: int) -> bool:
    if pid <= 0: return False
    if os.name == "nt":
        import ctypes
        h = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
        if not h: return False
        ctypes.windll.kernel32.CloseHandle(h)
        return True
    try: os.kill(pid, 0); return True
    except OSError: return False


def serve_status() -> tuple:
    """(running, pid, port)"""
    pf = pid_path()
    if not pf.exists(): return False, 0, 0
    try: pid = int(pf.read_text().strip() or "0")
    except: return False, 0, 0
    if not pid_alive(pid): pf.unlink(missing_ok=True); return False, 0, 0
    port = DEFAULT_SERVE_PORT
    try:
        txt = log_path().read_text(encoding="utf-8", errors="replace")
        m = re.search(r"port[:\s]+(\d+)", txt, re.IGNORECASE)
        if m: port = int(m.group(1))
    except: pass
    return True, pid, port


def start_serve(model_path: str = "", port: int = DEFAULT_SERVE_PORT,
                status_cb=None) -> tuple:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    running, old_pid, old_port = serve_status()
    if running:
        emit(f"Server already running on :{old_port}")
        return old_pid, old_port

    coli = find_coli()
    if not coli:
        emit("coli launcher not found")
        return 0, 0

    py = python_exe() or sys.executable
    model = model_path or find_model_path()
    if not model:
        emit("Model path not set")
        return 0, 0

    env = build_env(model)
    lf = open(log_path(), "w", encoding="utf-8", errors="replace")

    proc = subprocess.Popen(
        [py, str(coli), "serve", "--model", model, "--host", HOST, "--port", str(port)],
        stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
        cwd=str(repo_root()), env=env, creationflags=detached_flags(), close_fds=True)
    pid_path().write_text(str(proc.pid))
    emit(f"Server PID {proc.pid}, port {port}")
    return proc.pid, port


def stop_serve(status_cb=None) -> int:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    running, pid, _ = serve_status()
    if not running:
        emit("Server not running")
        pid_path().unlink(missing_ok=True)
        return 0
    try:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"],
                       capture_output=True, timeout=10, creationflags=hidden_flags())
        emit(f"Killed PID {pid}")
    except Exception as e:
        emit(f"Failed to kill: {e}")
    pid_path().unlink(missing_ok=True)
    return 0


def start_chat(model_path: str = "", status_cb=None) -> int:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    coli = find_coli()
    if not coli: emit("coli not found"); return 1
    py = python_exe() or sys.executable
    model = model_path or find_model_path()
    if not model: emit("Model not set"); return 1

    env = build_env(model)
    cmd = f'start "colibri Chat" "{py}" "{coli}" chat --model "{model}"'
    subprocess.Popen(cmd, shell=True, env=env, cwd=str(repo_root()),
                     creationflags=subprocess.CREATE_NEW_CONSOLE)
    emit("Chat launched in new console")
    return 0


def find_web_dir() -> Path | None:
    root = repo_root()
    p = root / "src" / "colibri" / "web"
    if p.is_dir() and (p / "package.json").is_file():
        return p
    return None


def web_pid_path() -> Path:
    return runtime_dir() / "colibri-web.pid"


def web_log_path() -> Path:
    return runtime_dir() / "colibri-web.log"


def web_port_path() -> Path:
    return runtime_dir() / "colibri-web.port"


WEB_DEFAULT_PORT = 8393


def web_status() -> tuple:
    pf = web_pid_path()
    if not pf.exists(): return False, 0, 0
    try: pid = int(pf.read_text().strip() or "0")
    except: return False, 0, 0
    if not pid_alive(pid): pf.unlink(missing_ok=True); return False, 0, 0
    port = WEB_DEFAULT_PORT
    try: port = int(web_port_path().read_text().strip() or str(WEB_DEFAULT_PORT))
    except: pass
    return True, pid, port


def start_web(port: int = WEB_DEFAULT_PORT, status_cb=None) -> tuple:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    running, old_pid, old_port = web_status()
    if running:
        emit(f"Web UI already running on :{old_port}")
        return old_pid, old_port

    web_dir = find_web_dir()
    if not web_dir:
        emit("Web UI dir not found (src/colibri/web)")
        return 0, 0

    node_modules = web_dir / "node_modules"
    if not node_modules.is_dir():
        emit("Web UI deps not installed — run: cd src/colibri/web && npm install")
        return 0, 0

    log_file = open(runtime_dir() / "colibri-web.log", "w", encoding="utf-8", errors="replace")
    proc = subprocess.Popen(
        ["npx", "vite", "--host", "127.0.0.1", "--port", str(port)],
        cwd=str(web_dir), stdout=log_file, stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL, creationflags=detached_flags(), close_fds=True)

    web_pid_path().write_text(str(proc.pid))
    web_port_path().write_text(str(port))
    emit(f"Web UI started (PID {proc.pid}) on http://127.0.0.1:{port}")
    return proc.pid, port


def stop_web(status_cb=None) -> int:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    running, pid, _ = web_status()
    if not running:
        emit("Web UI not running")
        web_pid_path().unlink(missing_ok=True)
        return 0
    try:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"],
                       capture_output=True, timeout=10, creationflags=hidden_flags())
        emit(f"Killed web UI PID {pid}")
    except Exception as e:
        emit(f"Failed to kill web UI: {e}")
    web_pid_path().unlink(missing_ok=True)
    web_port_path().unlink(missing_ok=True)
    return 0


def run_oneshot(prompt: str, model_path: str = "", ngen: int = 256,
                status_cb=None) -> tuple:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    coli = find_coli()
    if not coli: emit("coli not found"); return 1, ""
    py = python_exe() or sys.executable
    model = model_path or find_model_path()
    if not model: emit("Model not set"); return 1, ""

    env = build_env(model)
    env["NGEN"] = str(ngen)
    try:
        proc = subprocess.run(
            [py, str(coli), "run", "--model", model, prompt],
            capture_output=True, text=True, timeout=600, cwd=str(repo_root()),
            env=env, creationflags=hidden_flags())
        out = proc.stdout + "\n" + proc.stderr
        return proc.returncode, out
    except subprocess.TimeoutExpired:
        return 1, "TIMEOUT (600s)"
    except Exception as e:
        return 1, str(e)


def run_doctor(model_path: str = "", status_cb=None) -> tuple:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    coli = find_coli()
    if not coli: emit("coli not found"); return 1, ""
    py = python_exe() or sys.executable
    model = model_path or find_model_path()
    env = build_env(model)
    try:
        proc = subprocess.run(
            [py, str(coli), "doctor", "--model", model] if model else [py, str(coli), "doctor"],
            capture_output=True, text=True, timeout=120, cwd=str(repo_root()),
            env=env, creationflags=hidden_flags())
        return proc.returncode, proc.stdout
    except Exception as e:
        return 1, str(e)


def run_plan(model_path: str = "", status_cb=None) -> tuple:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    coli = find_coli()
    if not coli: emit("coli not found"); return 1, ""
    py = python_exe() or sys.executable
    model = model_path or find_model_path()
    env = build_env(model)
    try:
        proc = subprocess.run(
            [py, str(coli), "plan", "--model", model],
            capture_output=True, text=True, timeout=120, cwd=str(repo_root()),
            env=env, creationflags=hidden_flags())
        return proc.returncode, proc.stdout
    except Exception as e:
        return 1, str(e)


def cleanup_env_processes(status_cb=None) -> int:
    emit = status_cb or (lambda m: print(f"STATUS: {m}", flush=True))
    try:
        import psutil
    except ImportError:
        emit("psutil not available"); return 1
    venv = str(repo_root() / "colibri_env").lower()
    self_pid = os.getpid()
    killed = 0
    for p in psutil.process_iter(["pid", "name", "exe"]):
        try:
            if p.info["pid"] == self_pid: continue
            n = (p.info.get("name") or "").lower()
            if "python" not in n: continue
            e = (p.info.get("exe") or "").lower()
            if venv not in e: continue
            emit(f"Killing zombie PID {p.info['pid']}")
            p.kill(); killed += 1
        except: pass
    pid_path().unlink(missing_ok=True)
    emit(f"Cleaned {killed} process(es)")
    return 0


# ---- CLI entry ----
def main() -> int:
    import argparse
    ap = argparse.ArgumentParser()
    subp = ap.add_subparsers(dest="cmd")

    p = subp.add_parser("serve"); p.add_argument("--model", default=""); p.add_argument("--port", type=int, default=DEFAULT_SERVE_PORT)
    subp.add_parser("stop")
    p = subp.add_parser("run"); p.add_argument("prompt"); p.add_argument("--model", default="")
    p = subp.add_parser("doctor"); p.add_argument("--model", default="")
    p = subp.add_parser("plan"); p.add_argument("--model", default="")
    subp.add_parser("cleanup")

    args = ap.parse_args()
    if not args.cmd: ap.print_help(); return 1

    def emit(m): print(f"STATUS: {m}", flush=True)

    if args.cmd == "serve":
        pid, port = start_serve(args.model, args.port, emit)
        return 0 if pid else 1
    elif args.cmd == "stop":
        return stop_serve(emit)
    elif args.cmd == "run":
        rc, out = run_oneshot(args.prompt, args.model, status_cb=emit)
        print(out); return rc
    elif args.cmd == "doctor":
        rc, out = run_doctor(args.model, emit); print(out); return rc
    elif args.cmd == "plan":
        rc, out = run_plan(args.model, emit); print(out); return rc
    elif args.cmd == "cleanup":
        return cleanup_env_processes(emit)
    return 1


if __name__ == "__main__":
    sys.exit(main())
