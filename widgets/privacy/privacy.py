#!/usr/bin/env python3
"""Who is using the microphone or camera right now? (read-only, stdlib only)

  privacy.py [ignore-substring ...]    {"ok":true,"mic":["Zen"],"cam":["zoom"]}

 * mic : PipeWire nodes of class Stream/Input/Audio whose state is "running" (apps recording from a source).
         Streams that only watch a sink's monitor, volume-meter "peak detect" streams and the usual mixer apps are skipped.
 * cam : PipeWire Stream/Input/Video nodes that are running (apps reading a camera through PipeWire) plus any
         process of yours that has /dev/video* open (apps using the camera directly). pipewire/wireplumber
         themselves are ignored: they open the device just to enumerate it.
Extra args are exact executable basenames / absolute paths to treat as harmless (shown dimmed, never hidden).
"""
import json, os, shutil, subprocess, sys

# Streams are only treated as harmless when the *verified* executable (realpath of /proc/<pid>/exe, with the
# pid taken from the PipeWire client object that owns the node via the daemon's own `pipewire.sec.pid`, never from
# client-set names) is exactly one of these. Names such as application.name / media.name are attacker-controlled and are never used to hide anything.
# STREAM_BINARIES: native PipeWire clients that legitimately read streams (meters, graphs, effects).
#   NOT pipewire / pipewire-pulse / wireplumber: PulseAudio-protocol apps reach the graph *through* pipewire-pulse, so a
#   stream owned by that proxy could be any app and must never be treated as harmless.
# VIDEO_BINARIES: only for the /dev/video* opener check, where /proc/<pid>/exe really is the process holding the
#   device (pipewire / wireplumber open cameras just to enumerate them).
STREAM_BINARIES = ["easyeffects", "helvum", "qpwgraph", "carla", "cava", "quickshell"]
VIDEO_BINARIES = ["wireplumber", "pipewire"]
def _resolve(names):
    out = set()
    for b in names:
        path = shutil.which(b)
        if path: out.add(os.path.realpath(path))
    return out
STREAM_EXES, VIDEO_EXES = _resolve(STREAM_BINARIES), _resolve(VIDEO_BINARIES)
# user-supplied extras (explicit choice in widgetConfig.privacy.ignore): exact executable basenames or absolute paths
extra = set(a for a in sys.argv[1:] if a)

def exe_of(pid):
    try: return os.path.realpath("/proc/%d/exe" % int(pid))
    except Exception: return ""

def harmless(exe, exes):
    return bool(exe) and (exe in exes or exe in extra or os.path.basename(exe) in extra)

def pretty(props):
    for k in ("application.name", "application.process.binary", "node.description", "node.name"):
        v = props.get(k)
        if v and isinstance(v, str): return v.strip()
    return ""

def pw_streams():
    mic, cam, quiet = [], [], []
    try:
        d = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=4).stdout or "[]")
    except Exception:
        return mic, cam, quiet
    # daemon-set owner pid per client object (props.pipewire.sec.pid comes from the socket's peer credentials)
    clients = {o.get("id"): ((o.get("info") or {}).get("props") or {}).get("pipewire.sec.pid")
               for o in d if o.get("type") == "PipeWire:Interface:Client"}
    for o in d:
        if o.get("type") != "PipeWire:Interface:Node": continue
        info = o.get("info") or {}
        props = info.get("props") or {}
        cls = props.get("media.class", "")
        if info.get("state") != "running" or cls not in ("Stream/Input/Audio", "Stream/Input/Video"): continue
        name = pretty(props) or "Unknown app"
        kind = "cam" if cls == "Stream/Input/Video" else "mic"
        # `stream.capture.sink` is client-set, so it only de-emphasizes the stream, it does not hide it
        monitor = kind == "mic" and str(props.get("stream.capture.sink", "")).lower() == "true"
        # owner = the client object the daemon says created this node (never a client-set property)
        pid = clients.get(props.get("client.id"))
        exe = exe_of(pid) if pid else ""
        if monitor or harmless(exe, STREAM_EXES): quiet.append({"name": name, "kind": kind})
        else: (cam if kind == "cam" else mic).append(name)
    return mic, cam, quiet

def video_openers():
    res, quiet, me = [], [], os.getuid()
    try: pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except Exception: return res, quiet
    for pid in pids:
        try:
            if os.stat("/proc/" + pid).st_uid != me: continue
            fds = os.listdir("/proc/%s/fd" % pid)
        except Exception: continue
        hit = False
        for fd in fds:
            try:
                if os.readlink("/proc/%s/fd/%s" % (pid, fd)).startswith("/dev/video"): hit = True; break
            except Exception: continue
        if not hit: continue
        try: comm = open("/proc/%s/comm" % pid).read().strip()
        except Exception: comm = "Unknown app"
        # pipewire/wireplumber open the device just to enumerate it: recognised by exact verified exe, shown dimmed
        if harmless(exe_of(pid), VIDEO_EXES): quiet.append({"name": comm, "kind": "cam"})
        else: res.append(comm)
    return res, quiet

def uniq(l): return sorted(set(x for x in l if x), key=str.lower)

mic, cam, quiet = pw_streams()
vcam, vquiet = video_openers()
cam += vcam
quiet += vquiet
seen, q = set(), []
for x in quiet:
    k = (x["kind"], x["name"])
    if k not in seen: seen.add(k); q.append(x)
print(json.dumps({"ok": True, "mic": uniq(mic), "cam": uniq(cam), "quiet": q}))
