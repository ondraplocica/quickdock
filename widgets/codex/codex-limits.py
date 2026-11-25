#!/usr/bin/env python3
"""Codex usage limits for the quickdock codex widget. Read-only, no network, and it never opens auth.json.

The Codex CLI logs a `token_count` event into its session files (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, or
$CODEX_HOME/sessions) after each model turn; the event carries `rate_limits` with the current windows (primary,
secondary: used_percent, window_minutes, resets_at). We read the newest such record, so the numbers update while
Codex is being used and are the last known reading otherwise.

Prints one JSON object:
  {"ok": true, "ts": <epoch of the record>, "plan": "plus", "limit": "codex",
   "windows": [{"label": "Weekly", "used": 41.0, "minutes": 10080, "resets_at": 1796120376, "expired": false}],
   "credits": {"has_credits": false, "unlimited": false, "balance": "0"}}
or {"ok": false, "error": "..."}."""
import glob, json, os, time
from datetime import datetime

TAILS = (256 * 1024, 2 * 1024 * 1024, 16 * 1024 * 1024)      # how much of a file's end to scan, growing if needed
NEWEST_FILES = 8


def home():
    return os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")


def find_limits(o):
    if isinstance(o, dict):
        r = o.get("rate_limits")
        if isinstance(r, dict) and ("primary" in r or "secondary" in r):
            return r
        for v in o.values():
            f = find_limits(v)
            if f:
                return f
    elif isinstance(o, list):
        for v in o:
            f = find_limits(v)
            if f:
                return f
    return None


def last_record(path):
    size = os.path.getsize(path)
    for tail in TAILS:
        with open(path, "rb") as f:
            f.seek(max(0, size - tail))
            chunk = f.read().decode("utf-8", errors="replace")
        for line in reversed(chunk.splitlines()):
            if "rate_limits" not in line:
                continue
            try:
                j = json.loads(line)
            except ValueError:
                continue                                   # a cut-off first line of the tail
            r = find_limits(j)
            if r:
                return j.get("timestamp"), r
        if size <= tail:
            break
    return None


def label(minutes):
    if minutes == 300:
        return "5-hour"
    if minutes == 10080:
        return "Weekly"
    if minutes == 1440:
        return "Daily"
    if minutes % 1440 == 0:
        return "%d-day" % (minutes // 1440)
    if minutes % 60 == 0:
        return "%d-hour" % (minutes // 60)
    return "%d-min" % minutes


def epoch(ts):
    try:
        return int(datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp())
    except Exception:
        return 0


def main():
    files = sorted(glob.glob(os.path.join(home(), "sessions", "*", "*", "*", "rollout-*.jsonl")), key=os.path.getmtime, reverse=True)[:NEWEST_FILES]
    if not files:
        print(json.dumps({"ok": False, "error": "no Codex session files found (run codex once)"}))
        return
    for f in files:
        try:
            rec = last_record(f)
        except OSError:
            continue
        if not rec:
            continue
        ts, r = rec
        now = time.time()
        wins = []
        for key in ("primary", "secondary"):
            w = r.get(key)
            if isinstance(w, dict) and w.get("used_percent") is not None:
                minutes = int(w.get("window_minutes") or 0)
                resets = int(w.get("resets_at") or 0)
                wins.append({"label": label(minutes) if minutes else key, "used": float(w["used_percent"]), "minutes": minutes,
                             "resets_at": resets, "expired": bool(resets) and resets < now})
        c = r.get("credits")
        c = c if isinstance(c, dict) else {}
        print(json.dumps({"ok": bool(wins), "ts": epoch(ts), "plan": str(r.get("plan_type") or ""), "limit": str(r.get("limit_id") or ""),
                          "windows": wins, "credits": {"has_credits": c.get("has_credits") is True, "unlimited": c.get("unlimited") is True, "balance": str(c.get("balance") or "")}}))
        return
    print(json.dumps({"ok": False, "error": "no rate-limit record in the recent Codex sessions yet"}))


main()
