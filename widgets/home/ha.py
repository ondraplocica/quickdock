#!/usr/bin/env python3
"""Home Assistant helper (stdlib). Reads ~/.config/quickdock/ha.json {"url","token"}; the token never appears in argv.
  ha.py states <entity_id>...        -> {"ok":true,"entities":[{id,name,state,unit,domain,brightness,dimmable,...}]}
  ha.py search [query] [domain]      -> up to 24 entities matching name/id (controllable domains first), for the "pin more" picker
  ha.py status                       -> health: version, entity count, unavailable entities, latency
  ha.py call <domain> <service> <entity_id> [json-data]
"""
import json, os, sys, time, urllib.request, urllib.error
def out(o): print(json.dumps(o)); sys.exit(0)
try: cfg = json.load(open(os.path.expanduser("~/.config/quickdock/ha.json")))
except Exception: out({"ok": False, "error": "no-config"})
def req(method, path, body=None):
    r = urllib.request.Request(cfg["url"].rstrip("/") + path, json.dumps(body).encode() if body is not None else None, method=method,
        headers={"Authorization": "Bearer " + cfg["token"], "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=6) as f: return json.loads(f.read() or b"null")
    except urllib.error.HTTPError as e: out({"ok": False, "error": "http-%d" % e.code})
    except Exception: out({"ok": False, "error": "network"})
a = sys.argv[1:]
CONTROL = ("light", "switch", "fan", "input_boolean", "cover", "scene", "script", "button", "automation", "climate")

def brief(st):
    at = st.get("attributes", {}); eid = st["entity_id"]; b = at.get("brightness"); modes = at.get("supported_color_modes") or []
    return {"id": eid, "domain": eid.split(".")[0], "name": at.get("friendly_name", eid), "state": st.get("state"),
            "unit": at.get("unit_of_measurement", ""), "deviceClass": at.get("device_class", ""),
            "temp": at.get("current_temperature"),
            "brightness": round(b / 255, 3) if isinstance(b, (int, float)) else None,
            "dimmable": ("brightness" in modes and "onoff" not in modes) or isinstance(b, (int, float))}

if a[:1] == ["states"]:
    ids = a[1:]
    if len(ids) > 3:                       # one request beats many once a handful is pinned
        byid = {x["entity_id"]: x for x in req("GET", "/api/states")}
        out({"ok": True, "entities": [brief(byid[i]) if i in byid else {"id": i, "domain": i.split(".")[0], "name": i, "state": "unavailable", "unit": "", "deviceClass": "", "temp": None, "brightness": None, "dimmable": False} for i in ids]})
    out({"ok": True, "entities": [brief(req("GET", "/api/states/" + i)) for i in ids]})
elif a[:1] == ["search"]:
    q = (a[1] if len(a) > 1 else "").strip().lower(); dom = a[2] if len(a) > 2 else ""
    rows = [brief(x) for x in req("GET", "/api/states")]
    if dom: rows = [r for r in rows if r["domain"] == dom]
    if q: rows = [r for r in rows if q in r["name"].lower() or q in r["id"].lower()]
    rows = [r for r in rows if r["state"] != "unavailable"] + [r for r in rows if r["state"] == "unavailable"]
    rows.sort(key=lambda r: (CONTROL.index(r["domain"]) if r["domain"] in CONTROL else 99, r["state"] == "unavailable", r["name"].lower()))
    out({"ok": True, "entities": rows[:24], "total": len(rows)})
elif a[:1] == ["status"]:
    t0 = time.time()
    conf = req("GET", "/api/config")
    states = req("GET", "/api/states")
    ms = int((time.time() - t0) * 1000)
    bad = [{"id": x["entity_id"], "name": x.get("attributes", {}).get("friendly_name", x["entity_id"])} for x in states if x.get("state") == "unavailable"]
    out({"ok": True, "version": conf.get("version"), "name": conf.get("location_name"), "state": conf.get("state"),
         "entities": len(states), "unavailable": len(bad), "unavailableList": bad[:5], "latencyMs": ms})
elif a[:1] == ["call"] and len(a) >= 4:
    body = {"entity_id": a[3]}
    if len(a) > 4: body.update(json.loads(a[4]))
    req("POST", "/api/services/%s/%s" % (a[1], a[2]), body); out({"ok": True})
else: out({"ok": False, "error": "usage"})
