#!/usr/bin/env python3
"""Exchange-rate helper for the quickconvert widget (stdlib only).

  fx.py rates [--force]   {"ok":true,"base":"EUR","date":"YYYY-MM-DD","rates":{"CZK":24.3,...,"EUR":1},"stale":false,"age":123}

Source: the ECB reference rates via api.frankfurter.dev (same source as the Money app). Cached in
~/.cache/quickdock/fx.json and refreshed at most once an hour; if the network fails the stale cache is served
(stale: true). No key, no account, nothing sent but the request itself.
"""
import json, os, sys, time, urllib.request

CACHE_DIR = os.environ.get("QUICKDOCK_CACHE_DIR") or os.path.expanduser("~/.cache/quickdock")
CACHE = os.path.join(CACHE_DIR, "fx.json")
URL = "https://api.frankfurter.dev/v1/latest?base=EUR"
MAX_AGE = 3600

def out(o): print(json.dumps(o)); sys.exit(0)

def load():
    try:
        c = json.load(open(CACHE))
        if isinstance(c.get("rates"), dict) and isinstance(c.get("fetched"), (int, float)): return c
    except Exception: pass
    return None

def fetch():
    req = urllib.request.Request(URL, headers={"User-Agent": "quickdock-quickconvert"})
    with urllib.request.urlopen(req, timeout=8) as f: d = json.loads(f.read())
    rates = {k: float(v) for k, v in d["rates"].items() if isinstance(v, (int, float)) and v > 0 and len(k) == 3 and k.isalpha()}
    rates["EUR"] = 1.0
    c = {"base": "EUR", "date": str(d.get("date", "")), "rates": rates, "fetched": time.time()}
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as fh: json.dump(c, fh)
    os.replace(tmp, CACHE)
    return c

def main():
    force = "--force" in sys.argv
    c = load()
    stale = False
    if force or c is None or time.time() - c["fetched"] > MAX_AGE:
        try: c = fetch()
        except Exception as e:
            if c is None: out({"ok": False, "error": "offline"})
            stale = True
    out({"ok": True, "base": c["base"], "date": c["date"], "rates": c["rates"], "stale": stale, "age": int(time.time() - c["fetched"])})

if len(sys.argv) > 1 and sys.argv[1] == "rates": main()
else: out({"ok": False, "error": "usage: fx.py rates [--force]"})
