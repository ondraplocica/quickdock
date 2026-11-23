#!/usr/bin/env python3
"""Screen recorder helper for the quickdock recorder widget. Commands are run directly, never through a shell.

  recorder.py backends                                   -> {"backends": [...], "chosen": "wf-recorder" | null}
  recorder.py start <screen|region|window> <0|1> <dir>   -> {"ok": true, "file": ..., "backend": ...} or {"ok": false, "error": ...}
  recorder.py stop                                       -> {"ok": true, "file": ..., "exists": bool}
  recorder.py status                                     -> {"recording": bool, "file": ..., "started": epoch, "backend": ...}

Supported recorders: wf-recorder (also records audio) and wl-screenrec. State lives in $XDG_RUNTIME_DIR."""
import json, os, re, shutil, signal, subprocess, sys, time

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickdock-recorder.json")
LOG = STATE[:-5] + ".log"
KNOWN = ("wf-recorder", "wl-screenrec")
GEOM = re.compile(r"^-?\d+,-?\d+ \d+x\d+$")


def out(o):
    print(json.dumps(o))


def backends():
    return [b for b in KNOWN if shutil.which(b)]


def read_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return None


def alive(st):
    try:
        pid = int(st["pid"])
        os.kill(pid, 0)
        with open("/proc/%d/comm" % pid) as f:
            return f.read().strip() == st["backend"][:15]
    except Exception:
        return False


def status():
    st = read_state()
    if st and alive(st):
        return {"recording": True, "file": st["file"], "started": st["started"], "backend": st["backend"]}
    if st:
        try:
            os.remove(STATE)
        except OSError:
            pass
    return {"recording": False}


def run_text(cmd, timeout=60):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip()
    except Exception:
        return 1, ""


def focused_output():
    _, t = run_text(["hyprctl", "monitors", "-j"], 5)
    try:
        for m in json.loads(t):
            if m.get("focused"):
                return m["name"]
    except Exception:
        pass
    return None


def start(mode, audio, outdir):
    if status()["recording"]:
        return {"ok": False, "error": "already recording"}
    have = backends()
    if not have:
        return {"ok": False, "error": "no recorder installed (install wf-recorder)"}
    be = have[0]
    if mode not in ("screen", "region", "window"):
        return {"ok": False, "error": "bad mode"}
    outdir = os.path.expanduser(outdir)
    if not os.path.isabs(outdir):
        return {"ok": False, "error": "folder must be an absolute path"}
    try:
        os.makedirs(outdir, exist_ok=True)
    except OSError as e:
        return {"ok": False, "error": "cannot create %s: %s" % (outdir, e.strerror)}
    path = os.path.join(outdir, time.strftime("rec-%Y%m%d-%H%M%S.mp4"))
    cmd = [be, "-f", path]
    if mode == "region":
        rc, geo = run_text(["slurp"], 120)
        if rc != 0 or not GEOM.match(geo):
            return {"ok": False, "error": "cancelled"}
        cmd += ["-g", geo]
    elif mode == "window":
        _, t = run_text(["hyprctl", "activewindow", "-j"], 5)
        try:
            w = json.loads(t)
            geo = "%d,%d %dx%d" % (w["at"][0], w["at"][1], w["size"][0], w["size"][1])
        except Exception:
            return {"ok": False, "error": "no active window"}
        cmd += ["-g", geo]
    else:
        name = focused_output()
        if name:
            cmd += ["-o", name]
    if audio and be == "wf-recorder":
        cmd += ["--audio"]
    log = open(LOG, "w")
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    time.sleep(0.9)
    if proc.poll() is not None:
        try:
            msg = open(LOG).read().strip().splitlines()[-1]
        except Exception:
            msg = "the recorder exited"
        return {"ok": False, "error": msg[:160]}
    with open(STATE, "w") as f:
        json.dump({"pid": proc.pid, "file": path, "started": int(time.time()), "backend": be}, f)
    return {"ok": True, "file": path, "backend": be}


def stop():
    st = read_state()
    if not st or not alive(st):
        try:
            os.remove(STATE)
        except OSError:
            pass
        return {"ok": False, "error": "not recording"}
    pid = int(st["pid"])
    os.kill(pid, signal.SIGINT)                  # the recorders finalise the file on SIGINT
    for _ in range(80):
        time.sleep(0.1)
        if not alive(st):
            break
    else:
        os.kill(pid, signal.SIGTERM)
    try:
        os.remove(STATE)
    except OSError:
        pass
    return {"ok": True, "file": st["file"], "exists": os.path.exists(st["file"])}


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit("usage: recorder.py backends|start|stop|status")
    if a[0] == "backends":
        b = backends()
        out({"backends": b, "chosen": b[0] if b else None})
    elif a[0] == "status":
        out(status())
    elif a[0] == "stop":
        out(stop())
    elif a[0] == "start" and len(a) == 4:
        out(start(a[1], a[2] == "1", a[3]))
    else:
        sys.exit("bad arguments")


main()
