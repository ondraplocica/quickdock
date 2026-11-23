#!/usr/bin/env python3
"""Peripheral battery helper (stdlib, read-only).
  periph.py solaar    -> Logitech devices from `solaar show` (slow, ~6 s)
  periph.py system    -> upower devices + connected Bluetooth devices + a wired Keychron row when it has no battery source
Output: {"ok":true,"devices":[{"id","name","kind","pct":0-100|null,"state":"charging|discharging|full|wired|asleep|unknown","source","stale"?,"ts"?}]}
A Logitech device that is asleep has no battery reading; its last known reading is kept in a private cache and returned with "stale":true.
Names come from hardware: the widget renders them PlainText.
"""
import glob, json, os, re, stat, subprocess, sys, time
def sh(cmd, timeout=20):
    try: return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception: return ""
def clean(n): return re.sub(r"\b(\w+) \1\b", r"\1", n).strip()
def norm_state(s):
    s = (s or "").lower().replace("fully-charged", "full").replace("fully charged", "full").replace("pending-charge", "charging")
    for k in ("discharging", "charging", "full"):        # "discharging" must win: it contains "charging"
        if k in s: return k
    return "unknown"

KNOWN_KINDS = {"mouse", "keyboard", "headset", "headphones", "gaming-input", "touchpad", "trackball", "numpad", "phone", "tablet", "device"}
def guess_kind(name):
    n = name.lower()
    if re.search(r"master|anywhere|mouse|mx ergo|lift|trackball|g\d{3}", n): return "mouse"
    if re.search(r"keys|keyboard|k\d{3}|craft", n): return "keyboard"
    return "device"

def parse_solaar(text):
    devs, cur = [], None
    for line in text.splitlines():
        m = re.match(r"^  (\d+): (.+)$", line)
        if m: cur = {"id": "solaar:" + m.group(1) + ":" + m.group(2), "name": clean(m.group(2)), "kind": "mouse", "pct": None, "state": "unknown", "source": "solaar"}; devs.append(cur); continue
        if cur is None: continue
        k = re.match(r"^\s+Kind\s*:\s*(\w+)", line)
        if k: cur["kind"] = k.group(1).lower()
        b = re.match(r"^\s+Battery:\s*(\d+)%(?:,\s*(?:BatteryStatus\.)?(\w+))?", line)
        if b: cur["pct"] = int(b.group(1)); cur["state"] = norm_state(b.group(2))
    for d in devs:                                            # Solaar sometimes prints "Kind: none" while a device is idle
        if d["kind"] not in KNOWN_KINDS or d["kind"] == "device": d["kind"] = guess_kind(d["name"])
    return devs        # entries without a reading = asleep / offline; see with_last_known()

CACHE_MAX_AGE = 14 * 86400
SOLAAR_MIN_INTERVAL = 10 * 365 * 86400   # effectively never: `solaar show` starts a second Solaar process that talks to the same
                                         # receiver and REWRITES ~/.config/solaar/config.yaml. That is suspected of leaving the running
                                         # Solaar app unaware of the mouse waking up (settings like the thumb-wheel direction then
                                         # revert and are not re-applied). Only `periph.py solaar --force` (explicit) queries.
def _cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    d = os.path.join(base, "quickdock")
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
        st = os.lstat(d)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o022: return None
    except OSError: return None
    return d

def last_query_time():
    d = _cache_dir(); c = _load_cache(d) if d else {}
    m = c.get("_meta")
    return int(m.get("last_query", 0)) if isinstance(m, dict) else 0

def _load_cache(d):
    f = os.path.join(d, "periph-last.json")
    try:
        st = os.lstat(f)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_size > 65536: return {}
        data = json.load(open(f))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError): return {}

def _save_cache(d, data):
    f = os.path.join(d, "periph-last.json"); tmp = "%s.%d.tmp" % (f, os.getpid())
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as fh: json.dump(data, fh)
        os.replace(tmp, f)
    except OSError:
        try: os.unlink(tmp)
        except OSError: pass

def with_last_known(devs, now=None, queried=False):
    """Awake devices update the cache; asleep/offline ones (and ones missing right now) come back from it, stale:true."""
    now = int(now if now is not None else time.time())
    d = _cache_dir(); cache = _load_cache(d) if d else {}
    meta = cache.pop("_meta", None)
    out, seen = [], set()
    for dev in devs:
        key = dev["name"]; seen.add(key)
        if dev["pct"] is not None:
            cache[key] = {"pct": dev["pct"], "state": dev["state"], "kind": dev["kind"] if dev["kind"] in KNOWN_KINDS else guess_kind(key), "ts": now}
            out.append(dev)
        elif isinstance(cache.get(key), dict) and now - int(cache[key].get("ts", 0)) < CACHE_MAX_AGE:
            c = cache[key]
            out.append(dict(dev, pct=int(c.get("pct", 0)), kind=(str(c.get("kind")) if str(c.get("kind")) in KNOWN_KINDS and c.get("kind") != "device" else dev["kind"]), state="asleep", stale=True, ts=int(c.get("ts", 0))))
    for key, c in list(cache.items()):                       # cached but not listed by solaar at all right now
        if key in seen or not isinstance(c, dict): continue
        age = now - int(c.get("ts", 0))
        if age < CACHE_MAX_AGE:
            out.append({"id": "solaar:cached:" + key, "name": key, "kind": (str(c.get("kind")) if str(c.get("kind")) in KNOWN_KINDS and c.get("kind") != "device" else guess_kind(key)), "pct": int(c.get("pct", 0)),
                        "state": "asleep", "source": "solaar", "stale": True, "ts": int(c.get("ts", 0))})
    cache = {k: v for k, v in cache.items() if isinstance(v, dict) and now - int(v.get("ts", 0)) < CACHE_MAX_AGE}
    if queried: meta = {"last_query": now}
    if isinstance(meta, dict): cache["_meta"] = {"last_query": int(meta.get("last_query", 0))}
    if d: _save_cache(d, dict(list(cache.items())[:50]))
    return out

def parse_upower(blob):
    """`upower -i` output blocks for one device each"""
    d = {"kind": "device", "pct": None, "state": "unknown", "name": "", "source": "upower"}; ps = False
    for line in blob.splitlines():
        s = line.strip()
        if re.match(r"^(mouse|keyboard|headset|headphones|gaming-input|phone|tablet|touchpad|pen|media-player|speakers|monitor|bluetooth-generic|battery|ups)$", s): d["kind"] = s
        m = re.match(r"^(model|native-path|state|percentage|power supply|serial):\s*(.*)$", s)
        if not m: continue
        k, v = m.groups()
        if k == "model": d["name"] = clean(v)
        elif k == "native-path": d.setdefault("path", v)
        elif k == "state": d["state"] = norm_state(v)
        elif k == "percentage":
            n = re.match(r"(\d+)", v); d["pct"] = int(n.group(1)) if n else None
        elif k == "power supply": ps = v.lower() == "yes"
    if ps or d["pct"] is None: return None                # skip the laptop/system battery and meterless rows
    if not d["name"]: d["name"] = d.get("path", "Device")
    d["id"] = "upower:" + d.get("path", d["name"])
    return d

def upower_devices():
    out = []
    for p in sh(["upower", "-e"]).splitlines():
        if "DisplayDevice" in p or "line_power" in p or "battery_BAT" in p: continue
        d = parse_upower(sh(["upower", "-i", p]))
        if d: out.append(d)
    return out

def bluetooth_devices():
    out = []
    for line in sh(["bluetoothctl", "devices", "Connected"], 6).splitlines():
        m = re.match(r"^Device ([0-9A-F:]{17}) (.+)$", line.strip(), re.I)
        if not m: continue
        info = sh(["bluetoothctl", "info", m.group(1)], 6)
        b = re.search(r"Battery Percentage:\s*0x[0-9a-f]+\s*\((\d+)\)", info, re.I)
        if not b: continue
        ic = re.search(r"Icon:\s*(\S+)", info)
        kind = "headset" if ic and ("audio" in ic.group(1) or "headset" in ic.group(1)) else (ic.group(1) if ic else "device")
        out.append({"id": "bt:" + m.group(1), "name": clean(m.group(2)), "kind": kind, "pct": int(b.group(1)), "state": "unknown", "source": "bluetooth"})
    return out

def wired_keychron(have):
    names = set()
    for f in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"):
        try: t = open(f).read()
        except OSError: continue
        m = re.search(r"^HID_NAME=(.*Keychron.*)$", t, re.M)
        if m: names.add(clean(m.group(1)))
    out = []
    for n in sorted(names):
        if not any(n.lower() in h["name"].lower() or h["name"].lower() in n.lower() for h in have):
            out.append({"id": "wired:" + n, "name": n, "kind": "keyboard", "pct": None, "state": "wired", "source": "usb"})
    return out

def dedupe(devs):
    seen, out = set(), []
    for d in devs:
        k = d["name"].lower()
        if k in seen: continue
        seen.add(k); out.append(d)
    return out

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["solaar"]:
        now = int(time.time())
        if "--force" not in a and 0 <= now - last_query_time() < SOLAAR_MIN_INTERVAL:
            devs = with_last_known([], now)                   # cached readings only: no traffic to the mouse
        else:
            devs = with_last_known(parse_solaar(sh(["solaar", "show"], 25)), now, queried=True)
        print(json.dumps({"ok": True, "devices": devs}))
    elif a[:1] == ["system"]:
        devs = dedupe(upower_devices() + bluetooth_devices())
        print(json.dumps({"ok": True, "devices": devs + wired_keychron(devs)}))
    else: print(json.dumps({"ok": False, "error": "usage"}))
