#!/usr/bin/env python3
"""Calendar helper for the clock widget (read-only, stdlib + dateutil).

  cal.py events <from-date> <to-date>   events overlapping [from, to) as JSON ({"ok":true,"events":[...]})
  cal.py use-clipboard                  save the iCal link currently in the clipboard (wl-paste) as the source
  cal.py add <YYYY-MM-DDTHH:MM> <title> add a local event (stored in ~/.local/share/quickdock/events.json)
  cal.py remove <id>                    remove a local event

Source, in ~/.config/quickdock/calendar.json (mode 600, it contains a secret link):
  {"ics": ["https://calendar.google.com/calendar/ical/.../basic.ics"]}      <- simplest: Google Calendar
        settings -> "Secret address in iCal format". Works for any calendar that offers an .ics link.
  {"calendars": ["primary"]}                                                <- optional Google API (needs OAuth,
        see scripts/gauth.py)
Recurring events (RRULE/EXDATE/overrides) are expanded here for the .ics path; Google expands them for the API path.
"""
import ipaddress, json, os, re, subprocess, sys, uuid, urllib.parse, urllib.request
from datetime import datetime, date, time, timedelta, timezone
from zoneinfo import ZoneInfo

CFG_DIR = os.environ.get("QUICKDOCK_CONFIG_DIR") or os.path.expanduser("~/.config/quickdock")
DATA_DIR = os.environ.get("QUICKDOCK_DATA_DIR") or os.path.expanduser("~/.local/share/quickdock")
CFG = os.path.join(CFG_DIR, "calendar.json")
LOCAL_EVENTS = os.path.join(DATA_DIR, "events.json")
LOCAL = datetime.now().astimezone().tzinfo

def out(o): print(json.dumps(o)); sys.exit(0)
def fail(e): out({"ok": False, "error": e})

def load_cfg():
    try: return json.load(open(CFG))
    except Exception: return {}

# ---------------------------------------------------------------- iCal parsing
PROP = re.compile(r'^([A-Za-z0-9-]+)((?:;[^:;=]+=(?:"[^"]*"|[^;:]*))*):(.*)$')

def unfold(text):
    lines = []
    for ln in text.splitlines():
        if ln[:1] in (" ", "\t") and lines: lines[-1] += ln[1:]
        else: lines.append(ln)
    return lines

def unescape(v): return v.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")

def params_of(s):
    d = {}
    for m in re.finditer(r';([^:;=]+)=("[^"]*"|[^;:]*)', s): d[m.group(1).upper()] = m.group(2).strip('"')
    return d

def to_dt(value, params):
    """-> date (all-day) or aware datetime"""
    if params.get("VALUE") == "DATE" or (len(value) == 8 and value.isdigit()):
        return date(int(value[:4]), int(value[4:6]), int(value[6:8]))
    if value.endswith("Z"):
        return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
    dt = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
    try: tz = ZoneInfo(params["TZID"]) if "TZID" in params else LOCAL
    except Exception: tz = LOCAL
    return dt.replace(tzinfo=tz)

def parse_duration(v):
    m = re.match(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$', v)
    if not m: return timedelta(0)
    sign = -1 if m.group(1) == "-" else 1
    w, d, h, mi, s = (int(x or 0) for x in m.groups()[1:])
    return sign * timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)

def naive(x):  # sortable / comparable
    if isinstance(x, datetime): return x.astimezone(LOCAL).replace(tzinfo=None)
    return datetime.combine(x, time.min)

def parse_events(text):
    events, cur = [], None
    for ln in unfold(text):
        if ln == "BEGIN:VEVENT": cur = {"EXDATE": []}
        elif ln == "END:VEVENT":
            if cur is not None and "DTSTART" in cur: events.append(cur)
            cur = None
        elif cur is not None:
            m = PROP.match(ln)
            if not m: continue
            name, pr, val = m.group(1).upper(), params_of(m.group(2)), m.group(3)
            if name == "EXDATE":
                for part in val.split(","):
                    try: cur["EXDATE"].append(to_dt(part, pr))
                    except Exception: pass
            elif name in ("DTSTART", "DTEND", "RECURRENCE-ID"):
                try: cur[name] = to_dt(val, pr)
                except Exception: pass
            else: cur[name] = val
    return events

def occurrences(ev, w0, w1):
    """yield (start, end) for the instances of one VEVENT overlapping [w0, w1) (naive local datetimes)"""
    start = ev["DTSTART"]
    allday = not isinstance(start, datetime)
    if "DTEND" in ev: end = ev["DTEND"]
    elif "DURATION" in ev: end = (start + parse_duration(ev["DURATION"]))
    else: end = start + (timedelta(days=1) if allday else timedelta(0))
    dur = (naive(end) - naive(start)) if end is not None else timedelta(0)
    if "RRULE" in ev:
        from dateutil.rrule import rrulestr
        rule = ev["RRULE"]
        base = naive(start) if allday else start
        if allday or base.tzinfo is None: rule = re.sub(r'UNTIL=(\d{8}T\d{6})Z', r'UNTIL=\1', rule)
        try: rr = rrulestr(rule, dtstart=base)
        except Exception: rr = None
        if rr is not None:
            lo, hi = w0 - dur, w1
            if not allday and base.tzinfo is not None:
                lo, hi = lo.replace(tzinfo=LOCAL), hi.replace(tzinfo=LOCAL)
            skip = {naive(x) for x in ev["EXDATE"]}
            for o in rr.between(lo, hi, inc=True):
                n = naive(o)
                if n in skip: continue
                yield (o if not allday else n.date(), (o + dur) if not allday else (n + dur).date(), n, n + dur)
            return
    n0, n1 = naive(start), naive(start) + dur
    if n0 < w1 and (n1 > w0 or n0 >= w0):
        yield (start, end, n0, n1)

def ics_name(text):
    m = re.search(r'^X-WR-CALNAME(?:;[^:]*)?:(.*)$', text, re.M)
    return unescape(m.group(1).strip()) if m else ""

def ics_events(text, w0, w1):
    evs = parse_events(text)
    overridden = {(e.get("UID"), naive(e["RECURRENCE-ID"])) for e in evs if "RECURRENCE-ID" in e}
    res = []
    for e in evs:
        if e.get("STATUS", "").upper() == "CANCELLED": continue
        for (s, en, n0, n1) in occurrences(e, w0, w1):
            if "RECURRENCE-ID" not in e and (e.get("UID"), n0) in overridden: continue
            allday = not isinstance(s, datetime)
            res.append({"id": "%s@%s" % (e.get("UID", ""), n0.isoformat()), "title": unescape(e.get("SUMMARY", "(no title)")),
                        "location": unescape(e.get("LOCATION", "")), "allDay": allday,
                        "start": s.isoformat() if not allday else s.isoformat(),
                        "end": (en.isoformat() if en is not None else None), "_k": n0})
    res.sort(key=lambda r: r["_k"])
    for r in res: del r["_k"]
    return res

# Providers that publish calendar links without a .ics path (the rest must end in .ics)
KNOWN_HOSTS = ("google.com", "icloud.com", "outlook.live.com", "outlook.office365.com", "office365.com", "fastmail.com", "proton.me")

def check_link(link, from_clipboard=False):
    """Return a normalised https URL, or None. Clipboard links are stricter: public https hosts only."""
    link = link.strip()
    if link.lower().startswith("webcal://"): link = "https://" + link[9:]
    try: u = urllib.parse.urlsplit(link)
    except ValueError: return None
    host = (u.hostname or "").lower()
    if u.scheme not in (("https",) if from_clipboard else ("https", "http")) or not host or u.username or u.password: return None
    if from_clipboard:
        try:
            ip = ipaddress.ip_address(host)
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast: return None
        except ValueError:
            if host in ("localhost",) or host.endswith((".local", ".internal", ".lan")): return None
        if not (u.path.lower().endswith(".ics") or any(host == h or host.endswith("." + h) for h in KNOWN_HOSTS)): return None
    return link

def load_local():
    try: return json.load(open(LOCAL_EVENTS))
    except Exception: return []

def save_local(items):
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = LOCAL_EVENTS + ".tmp"
    with open(tmp, "w") as f: json.dump(items, f)
    os.replace(tmp, LOCAL_EVENTS)

def local_events(w0, w1):
    res = []
    for e in load_local():
        try: s_ = datetime.fromisoformat(e["start"])
        except Exception: continue
        en = s_ + timedelta(minutes=int(e.get("minutes", 60)))
        if s_ < w1 and en > w0:
            res.append({"id": "local:" + e["id"], "title": e["title"], "location": "", "allDay": False, "cal": "local",
                        "start": s_.replace(tzinfo=LOCAL).isoformat(), "end": en.replace(tzinfo=LOCAL).isoformat()})
    return res

def fetch(url):
    if urllib.parse.urlsplit(url).scheme not in ("http", "https"): raise ValueError("unsupported scheme")   # no file:// etc.
    req = urllib.request.Request(url, headers={"User-Agent": "quickdock"})
    with urllib.request.urlopen(req, timeout=20) as r: return r.read().decode("utf-8", "replace")

# ---------------------------------------------------------------- commands
a = sys.argv[1:]
if a[:1] == ["use-clipboard"]:
    try: link = subprocess.run(["wl-paste", "--no-newline"], capture_output=True, text=True, timeout=3).stdout.strip()
    except Exception: fail("no-clipboard")
    link = check_link(link, from_clipboard=True)
    if not link: fail("not-ical")
    cfg = load_cfg(); cfg["ics"] = [link]
    os.makedirs(os.path.dirname(CFG), exist_ok=True)
    fd = os.open(CFG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f: json.dump(cfg, f)
    out({"ok": True})

if len(a) >= 3 and a[0] == "add":
    try: when = datetime.fromisoformat(a[1])
    except Exception: fail("bad-time")
    title = " ".join(a[2:]).strip()[:200]
    if not title: fail("empty")
    items = load_local(); items.append({"id": uuid.uuid4().hex[:8], "title": title, "start": when.replace(tzinfo=None).isoformat(timespec="minutes"), "minutes": 60})
    save_local(items); out({"ok": True})

if len(a) >= 2 and a[0] == "remove":
    save_local([e for e in load_local() if e["id"] != a[1].replace("local:", "")]); out({"ok": True})

if len(a) >= 3 and a[0] == "events":
    cfg = load_cfg()
    d0, d1 = date.fromisoformat(a[1]), date.fromisoformat(a[2])
    w0, w1 = datetime.combine(d0, time.min), datetime.combine(d1, time.min)
    if cfg.get("ics"):
        events, names = [], []
        for url in cfg["ics"]:
            try:
                text = fetch(url)
                names.append(ics_name(text))
                for e in ics_events(text, w0, w1): e["cal"] = "feed"; events.append(e)
            except Exception: fail("network")
        events += local_events(w0, w1)
        events.sort(key=lambda e: e["start"][:10])
        out({"ok": True, "events": events, "source": "ics", "hasFeed": True, "feedName": next((n for n in names if n), "Calendar")})
    if cfg.get("calendars") or os.path.exists(os.path.expanduser("~/.config/quickdock/google-token.json")):
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts"))
        from gauth import call
        events = []
        for cid in (cfg.get("calendars") or ["primary"]):
            q = urllib.parse.urlencode({"timeMin": a[1] + "T00:00:00Z", "timeMax": a[2] + "T00:00:00Z", "singleEvents": "true",
                                        "orderBy": "startTime", "maxResults": 250, "fields": "items(id,summary,location,start,end,status)"})
            r = call("GET", "https://www.googleapis.com/calendar/v3/calendars/%s/events?%s" % (urllib.parse.quote(cid, safe=""), q))
            for e in r.get("items", []):
                if e.get("status") == "cancelled": continue
                s, en = e.get("start", {}), e.get("end", {})
                events.append({"id": e["id"], "title": e.get("summary", "(no title)"), "location": e.get("location", ""),
                               "start": s.get("dateTime") or s.get("date"), "end": en.get("dateTime") or en.get("date"), "allDay": "date" in s, "cal": "feed"})
        events += local_events(w0, w1)
        out({"ok": True, "events": events, "source": "google", "hasFeed": True, "feedName": "Google Calendar"})
    out({"ok": True, "events": local_events(w0, w1), "source": "local", "hasFeed": False, "feedName": ""})
fail("usage")
