"""A stand-in for the add-on for testing the app: made-up flights shaped like the real API (python3 tools/mock_addon.py <www dir> <port>)."""
import json, math, os, random, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from datetime import datetime, timezone

WWW = sys.argv[1]
PORT = int(sys.argv[2])
NOW = time.time()
M = 60
H = 3600

AP = {
    "EWR": ("Newark Liberty International Airport", "Newark", 40.6925, -74.1687, "America/New_York"),
    "BNA": ("Nashville International Airport", "Nashville", 36.1245, -86.6782, "America/Chicago"),
    "FLL": ("Fort Lauderdale-Hollywood International Airport", "Fort Lauderdale", 26.0726, -80.1527, "America/New_York"),
    "MIA": ("Miami International Airport", "Miami", 25.7959, -80.2870, "America/New_York"),
    "MYR": ("Myrtle Beach International Airport", "Myrtle Beach", 33.6797, -78.9283, "America/New_York"),
    "CUR": ("Curacao International Airport", "Curacao", 12.1889, -68.9598, "America/Curacao"),
    "MCO": ("Orlando International Airport", "Orlando", 28.4294, -81.3089, "America/New_York"),
    "TPA": ("Tampa International Airport", "Tampa", 27.9755, -82.5332, "America/New_York"),
    "RSW": ("Southwest Florida International Airport", "Fort Myers", 26.5362, -81.7552, "America/New_York"),
    "SJU": ("Luis Munoz Marin International Airport", "San Juan", 18.4394, -66.0018, "America/Puerto_Rico"),
    "LAX": ("Los Angeles International Airport", "Los Angeles", 33.9416, -118.4085, "America/Los_Angeles"),
    "SFO": ("San Francisco International Airport", "San Francisco", 37.6190, -122.375, "America/Los_Angeles"),
    "DEN": ("Denver International Airport", "Denver", 39.8617, -104.673, "America/Denver"),
    "IAH": ("George Bush Intercontinental Airport", "Houston", 29.9844, -95.3414, "America/Chicago"),
    "ORD": ("O'Hare International Airport", "Chicago", 41.9786, -87.9048, "America/Chicago"),
    "ATL": ("Hartsfield-Jackson Atlanta International Airport", "Atlanta", 33.6407, -84.4277, "America/New_York"),
    "BOS": ("Logan International Airport", "Boston", 42.3656, -71.0096, "America/New_York"),
    "PBI": ("Palm Beach International Airport", "West Palm Beach", 26.6832, -80.0956, "America/New_York"),
    "SAV": ("Savannah/Hilton Head International Airport", "Savannah", 32.1276, -81.2021, "America/New_York"),
    "AUS": ("Austin-Bergstrom International Airport", "Austin", 30.1975, -97.6664, "America/Chicago"),
    "PHX": ("Phoenix Sky Harbor International Airport", "Phoenix", 33.4342, -112.0116, "America/Phoenix"),
    "LAS": ("Harry Reid International Airport", "Las Vegas", 36.0840, -115.1537, "America/Los_Angeles"),
    "SEA": ("Seattle-Tacoma International Airport", "Seattle", 47.4502, -122.3088, "America/Los_Angeles"),
    "SAN": ("San Diego International Airport", "San Diego", 32.7338, -117.1933, "America/Los_Angeles"),
    "MSY": ("Louis Armstrong New Orleans International Airport", "New Orleans", 29.9934, -90.2580, "America/Chicago"),
    "STT": ("Cyril E. King Airport", "St. Thomas", 18.3373, -64.9734, "America/St_Thomas"),
    "PUJ": ("Punta Cana International Airport", "Punta Cana", 18.5674, -68.3634, "America/Santo_Domingo"),
    "CUN": ("Cancun International Airport", "Cancun", 21.0365, -86.8771, "America/Cancun"),
    "AUA": ("Queen Beatrix International Airport", "Aruba", 12.5014, -70.0152, "America/Aruba"),
    "GUA": ("La Aurora International Airport", "Guatemala City", 14.5833, -90.5275, "America/Guatemala"),
    "BDA": ("L.F. Wade International Airport", "Bermuda", 32.3640, -64.6787, "Atlantic/Bermuda"),
    "LGA": ("LaGuardia Airport", "New York", 40.7769, -73.874, "America/New_York"),
    "CLT": ("Charlotte Douglas International Airport", "Charlotte", 35.214, -80.9431, "America/Charlotte" if False else "America/New_York"),
    "SLC": ("Salt Lake City International Airport", "Salt Lake City", 40.7899, -111.9791, "America/Denver"),
}


def ap(c):
    n, city, la, lo, tz = AP[c]
    return {"iata": c, "icao": "K" + c if la > 24 and lo < -60 else "T" + c, "name": n, "city": city, "lat": la, "lon": lo, "tz": tz}


def gc(a, b, n=40, upto=1.0):
    R = math.pi / 180
    la1, lo1, la2, lo2 = a["lat"] * R, a["lon"] * R, b["lat"] * R, b["lon"] * R
    d = 2 * math.asin(math.sqrt(math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2))
    out = []
    for i in range(n + 1):
        f = i / n * upto
        A, B = math.sin((1 - f) * d) / math.sin(d), math.sin(f * d) / math.sin(d)
        x = A * math.cos(la1) * math.cos(lo1) + B * math.cos(la2) * math.cos(lo2)
        y = A * math.cos(la1) * math.sin(lo1) + B * math.cos(la2) * math.sin(lo2)
        z = A * math.sin(la1) + B * math.sin(la2)
        out.append([math.atan2(z, math.hypot(x, y)) / R, math.atan2(y, x) / R])
    return out, d * 3440.065


def T(s=None, e=None, a=None):
    return {"scheduled": s, "estimated": e, "actual": a}


# ---- UA2677 BNA-EWR, in the air, 1h16m late
out_a = NOW - 75 * M
out_s = out_a - 76 * M
off_a = out_a + 20 * M
on_e = NOW + 43 * M
in_e = NOW + 54 * M
in_s = in_e - 72 * M
pts, dist = gc(ap("BNA"), ap("EWR"), 50, 0.68)
track = [[p[0], p[1], 37000, 470, off_a + i * 60] for i, p in enumerate(pts)]
live = {"lat": pts[-1][0], "lon": pts[-1][1], "alt_ft": 36937, "gs_kt": 480, "heading": None, "at": NOW - 20, "src": "adsb.lol"}
nas_ewr = {"key": "EWR|delay|arr", "kind": "delay", "airport": "EWR", "label": "Arrival delays", "detail": "avg 43 min", "dir": "arr", "reason": "volume"}


def rot_leg(ident, o, d, out_s_, in_s_, arr_dly, phase="arrived"):
    return {"display_ident": ident, "ident": ident, "origin": ap(o), "destination": ap(d), "phase": phase,
            "status": "Arrived", "tail": "N38459", "aircraft_type": "B739",
            "times": {"out": T(out_s_, None, out_s_ + 60), "off": T(out_s_ + 900, None, out_s_ + 1000),
                      "on": T(in_s_ - 600, None, in_s_ - 600 + arr_dly * 60), "in": T(in_s_, None, in_s_ + arr_dly * 60)},
            "arr_delay": arr_dly, "dep_delay": 1}


leg1 = {
    "id": "L1", "ident": "UAL2677", "display": "UA2677", "airline": "UAL", "flight_no": "2677", "dep": "BNA", "arr": "EWR",
    "dh": False, "extra": False, "kind": None, "sched_out": out_s, "sched_in": in_s, "summary": "UA2677 BNA-EWR",
    "source": "FlightAware", "updated": NOW - 40, "phase": "airborne", "status": "En Route", "watching": True, "finished": False,
    "problems": [], "delay": 76, "arr_delay": 72, "turn": None, "dep_ap": ap("BNA"), "arr_ap": ap("EWR"), "nas": [nas_ewr],
    "flight": {"times": {"out": T(out_s, None, out_a), "off": T(out_s + 10 * M, None, off_a), "on": T(in_s - 11 * M, on_e, None), "in": T(in_s, in_e, None)},
               "origin": {"gate": "B8", "terminal": "Main"}, "destination": {"gate": "A22", "terminal": "A", "baggage": "3"},
               "aircraft_type": "B739", "aircraft_name": "Boeing 737-900ER", "tail": "N38459", "distance_nm": 646, "last_position": track[-1],
               "time_src": {"in": "FlightAware Foresight"}},
    "live": live,
}
# ---- the trip on the 20th: EWR-FLL, FLL-EWR (1h12m sit), then EWR-FLL the 21st
def day_at(days, hh, mm, tz_off=-4):
    d = datetime.fromtimestamp(NOW + days * 86400, timezone.utc)
    base = datetime(d.year, d.month, d.day, tzinfo=timezone.utc).timestamp()
    return base + (hh - tz_off) * H + mm * M


def sched_leg(id_, disp, dep, arr, so, si, gate=None, extra=None):
    L = {"id": id_, "ident": "UAL" + disp[2:], "display": disp, "airline": "UAL", "flight_no": disp[2:], "dep": dep, "arr": arr,
         "dh": False, "extra": False, "kind": None, "sched_out": so, "sched_in": si, "summary": f"{disp} {dep}-{arr}", "source": "FlightAware",
         "phase": "scheduled", "status": "Scheduled", "watching": False, "finished": False, "problems": [], "delay": None, "arr_delay": None,
         "turn": None, "dep_ap": ap(dep), "arr_ap": ap(arr), "nas": [],
         "flight": {"times": {"out": T(so), "off": T(so + 15 * M), "on": T(si - 8 * M), "in": T(si)}, "origin": {"gate": gate}, "destination": {},
                    "aircraft_type": "B39M", "aircraft_name": "Boeing 737 MAX 9", "distance_nm": 930}}
    if extra:
        L.update(extra)
    return L


s2 = day_at(3, 8, 45); i2 = day_at(3, 11, 53)
s3 = day_at(3, 13, 5); i3 = day_at(3, 16, 3)
s4 = day_at(4, 9, 15); i4 = day_at(4, 12, 21)
legs = [leg1,
        sched_leg("L2", "UA2151", "EWR", "FLL", s2, i2, "C71"),
        sched_leg("L3", "UA1611", "FLL", "EWR", s3, i3),
        sched_leg("L4", "UA2151", "EWR", "FLL", s4, i4)]
# a friend's flight boarding soon, a little late
s5 = NOW + 2 * H + 10 * M
legs.append(sched_leg("L5", "UA1998", "EWR", "MCO", s5, s5 + 2 * H + 40 * M, "C93",
                      {"extra": True, "kind": "friend", "watching": True, "status": "Delayed",
                       "problems": [{"level": "warn", "text": "Departure delayed 25 min"}]}))
legs[-1]["flight"]["times"]["out"] = T(s5, s5 + 25 * M)
legs[-1]["flight"]["times"]["in"] = T(s5 + 2 * H + 40 * M, s5 + 3 * H + 2 * M)

rotation = [rot_leg("UA2676", "EWR", "BNA", NOW - 6 * H, NOW - 4 * H - 47 * M, -9),
            rot_leg("UA1874", "MYR", "EWR", NOW - 9 * H, NOW - 7 * H - 9 * M, -29),
            rot_leg("UA1875", "EWR", "MYR", NOW - 12 * H, NOW - 10 * H, 4),
            rot_leg("UA444", "FLL", "EWR", NOW - 16 * H, NOW - 13 * H, 12)]

full1 = dict(leg1)
full1["flight"] = dict(leg1["flight"], track=track, waypoints=gc(ap("BNA"), ap("EWR"), 30)[0])
full1.update(rotation=rotation, inbound=rotation[0], wx={
    "KBNA": {"raw": "KBNA 172253Z 18006KT 10SM CLR 16/04 A3012", "category": "VFR"},
    "KEWR": {"raw": "KEWR 172251Z 31012KT 10SM FEW250 10/M02 A3020", "category": "VFR"}},
    route_stats={"flights": 14, "on_time_pct": 64, "avg_arr_delay": 11.2}, tail_count=3,
    history=[{"at": NOW - 300, "sources": ["FlightAware", "ADS-B"], "changes": [{"field": "arrival", "from": "7:58 PM", "to": "8:03 PM"}], "seen": []}],
    alerts=[{"level": "warn", "title": "UA2677 departed 1h16m late", "message": "Pushed from B8 at 4:53 PM CDT", "at": out_a}])

alerts = [{"level": "warn", "title": "UA2677 departed 1h16m late", "message": "Pushed from B8 at 4:53 PM CDT", "at": out_a},
          {"level": "info", "title": "UA2677 gate A22", "message": "Arrival gate A22, bags on belt 3", "at": NOW - 2 * H}]

state = {"now": NOW, "version": "3.22.3", "home_tz": "America/New_York", "legs": legs, "nas": [nas_ewr], "nas_at": NOW - 120,
         "nas_error": None, "wx": {}, "alerts": alerts, "schedule": {"checked": NOW - 600, "count": 4}, "worker": {"busy": False},
         "settings": {"watch_hours": 12, "delay_threshold_minutes": 15, "min_turn_minutes": 30, "airline_icao": "UAL", "live_positions": True},
         "map_tiles": {"url": "", "key": "", "google": "TESTKEY", "mapbox": "pk.TEST"}, "notify_target": "notify.mobile_app_erics_iphone", "gemini": False, "aeroapi": True,
         "swim": {"status": "off"}, "tfdm": {"status": "off"}, "stdds": {"status": "connected"}, "backup": {"state": "synced", "last": NOW - 900}}

# ---- History
random.seed(4)
dests = ["MIA", "FLL", "MCO", "TPA", "RSW", "SJU", "LAX", "SFO", "DEN", "IAH", "ORD", "ATL", "BOS", "PBI", "SAV", "AUS", "PHX", "LAS",
         "SEA", "SAN", "MSY", "STT", "PUJ", "CUN", "AUA", "CUR", "BNA", "MYR", "GUA", "BDA", "SLC"]
weights = [14, 16, 12, 7, 6, 6, 3, 3, 4, 4, 4, 3, 2, 5, 3, 2, 2, 2, 1, 1, 2, 3, 3, 3, 2, 3, 4, 3, 1, 1, 1]
hist = []
for i in range(350):
    t0 = NOW - (2 + i * 1.6) * 86400 - random.randint(0, 40000)
    d = random.choices(dests, weights)[0]
    out_bound = i % 2 == 0
    dep, arr = ("EWR", d) if out_bound else (d, "EWR")
    _, nmi = gc(ap(dep), ap(arr), 2)
    blk = (nmi / 430 + 0.45) * H
    dly = random.choice([-12, -8, -5, -3, 0, 2, 4, 6, 9, 14, 18, 25, 33, 47, 62, 95, -15, 1, 3, 70])
    so = t0
    ao = so + max(-3, dly - 4) * M
    ai = so + blk + dly * M
    num = random.randint(200, 2999)
    ac = random.choices(["Boeing 737-900ER", "Boeing 737 MAX 9", "Boeing 737-800", "Boeing 737 MAX 8", "Boeing 737-700"], [34, 25, 22, 12, 7])[0]
    date = datetime.fromtimestamp(so, timezone.utc).strftime("%Y-%m-%d")
    hist.append({"id": f"H{i}", "date": date, "display": f"UA{num}", "ident": f"UAL{num}", "airline": "UAL", "dep": dep, "arr": arr,
                 "diverted_to": None, "cancelled": False, "kind": "calendar", "source": "flighty" if i > 40 else "tracked", "aircraft": ac,
                 "type": "B739", "tail": f"N{random.randint(37000, 38999)}", "distance_nm": round(nmi), "has_track": i < 40, "dh": False,
                 "dep_gate": f"C{random.randint(70, 140)}", "arr_gate": f"D{random.randint(1, 40)}", "route": None,
                 "times": {"out": {"s": so, "a": ao}, "off": {"s": so + 900, "a": ao + 1100}, "on": {"s": so + blk - 600, "a": ai - 480}, "in": {"s": so + blk, "a": ai}},
                 "dep_delay": (ao - so) / 60, "arr_delay": dly, "block_min": (ai - ao) / 60, "air_min": (ai - ao - 1580) / 60,
                 "dep_tz": AP[dep][4], "arr_tz": AP[arr][4]})


def stats(sel):
    fl = [f for f in sel if not f["cancelled"]]
    arr = [f["arr_delay"] for f in fl if f["arr_delay"] is not None]
    def top(key, k=8):
        c = {}
        for f in fl:
            v = key(f)
            if v:
                c[v] = c.get(v, 0) + 1
        return sorted(c.items(), key=lambda x: (-x[1], x[0]))[:k]
    aps = {a for f in fl for a in (f["dep"], f["arr"])}
    return {"flights": len(fl), "cancelled": 0, "diverted": 0, "distance_nm": sum(f["distance_nm"] for f in fl),
            "air_hours": round(sum(f["air_min"] for f in fl) / 60, 1), "block_hours": round(sum(f["block_min"] for f in fl) / 60, 1),
            "airports": len(aps), "tails": len({f["tail"] for f in fl}), "routes": len({tuple(sorted((f["dep"], f["arr"]))) for f in fl}),
            "on_time_pct": round(100 * sum(1 for d in arr if d < 15) / len(arr)) if arr else None,
            "avg_arr_delay": round(sum(arr) / len(arr), 1) if arr else None, "avg_dep_delay": 6.2, "early_pct": 22, "late_30_pct": 14,
            "top_routes": top(lambda f: f"{f['dep']}–{f['arr']}"), "top_airports": top(lambda f: f["arr"]),
            "top_aircraft": top(lambda f: f["aircraft"]), "top_tails": top(lambda f: f["tail"], 6),
            "late_routes": [["EWR–MIA", 20, 24.1, .6], ["EWR–SJU", 6, 18.0, .66]], "late_airports": [],
            "by_hour": [["06–09", 40, 2.1], ["09–12", 60, 6.4], ["12–15", 70, 11.0], ["15–18", 80, 17.5], ["18–21", 60, 22.0]],
            "longest": fl[0] if fl else None, "worst_delay": fl[1] if len(fl) > 1 else None,
            "years": sorted({f["date"][:4] for f in sel}, reverse=True)}


class H_(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if not isinstance(body, (bytes, bytearray)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path, _, q = self.path.partition("?")
        if path in ("/", ""):
            path = "/index.html"
        if path == "/api/state":
            return self._send(200, state)
        m = re.match(r"^/api/leg/(\w+)$", path)
        if m:
            lid = m.group(1)
            if lid == "L1":
                return self._send(200, full1)
            L = next((x for x in legs if x["id"] == lid), None)
            if not L:
                return self._send(404, {"error": "nf"})
            return self._send(200, dict(L, rotation=[], history=[], alerts=[], wx={}))
        m = re.match(r"^/api/live/(\w+)$", path)
        if m:
            return self._send(200, {"live": live, "track": []})
        if path == "/api/history":
            year = re.search(r"year=(\d{4})", q)
            sel = [f for f in hist if not year or f["date"].startswith(year.group(1))]
            aps = {c: {k: v for k, v in ap(c).items() if k in ("city", "name", "lat", "lon")} for f in sel for c in (f["dep"], f["arr"])}
            return self._send(200, {"year": year.group(1) if year else "", "years": sorted({f["date"][:4] for f in hist}, reverse=True),
                                    "total": len(hist), "flighty_count": 300, "stats": stats(sel), "flights": sel, "airports": aps})
        m = re.match(r"^/api/history/(H\d+)$", path)
        if m:
            f = next(x for x in hist if x["id"] == m.group(1))
            tr = gc(ap(f["dep"]), ap(f["arr"]), 40)[0]
            return self._send(200, dict(f, track=[[p[0], p[1], 30000, 450, 0] for p in tr], dep_ap=ap(f["dep"]), arr_ap=ap(f["arr"]),
                                        route_stats={"flights": 22, "on_time_pct": 77, "avg_arr_delay": 4.0}, tail_count=2))
        if path == "/api/lookup":
            d0 = NOW - (NOW % 86400) + 4 * H
            mk = lambda fid, o, d, h: {"fa_id": fid, "ident": "UAL1102", "display": "UA1102", "dep": o, "arr": d, "dep_city": AP[o][1], "arr_city": AP[d][1],
                "dep_tz": AP[o][4], "arr_tz": AP[d][4], "out": {"scheduled": d0 + h * H, "estimated": d0 + h * H + (1200 if fid == "B" else 0)},
                "in": {"scheduled": d0 + (h + 3) * H}, "status": "Scheduled", "cancelled": False, "aircraft_type": "B739", "tail": "N37413"}
            return self._send(200, {"mode": "list", "date": "2026-10-17", "ident": "UA1102", "flights": [mk("A", "MIA", "EWR", 7), mk("B", "EWR", "MIA", 13)]})
        if path == "/api/airports/status":
            items = [("LGA", {"kind": "gdp", "label": "Ground delay program", "detail": "avg 87 min, max 140 min", "reason": "wind", "end": NOW + 3 * H, "scope": ["ZNY", "ZBW"], "key": "LGA|gdp|1"}),
                     ("EWR", nas_ewr), ("CLT", {"kind": "gs", "label": "Ground stop", "detail": "", "reason": "thunderstorms", "end": NOW + 45 * M, "scope": ["ZTL"], "key": "CLT|gs|1"}),
                     ("ORD", {"kind": "delay", "label": "Departure delay trend", "detail": "avg 27 min and increasing", "reason": "volume", "key": "ORD|delay|Dep"}),
                     ("PHX", {"kind": "delay", "label": "Arrival delay trend", "detail": "16–30 min", "reason": "runway construction", "key": "PHX|delay|Arr"}),
                     ("BOS", {"kind": "deice", "label": "Deicing", "detail": "", "reason": "", "key": "BOS|deice"})]
            aps = {}
            for c, n in items:
                a = ap(c); n = dict(n, airport=c)
                aps.setdefault(c, {"code": c, "name": a["name"], "city": a["city"], "lat": a["lat"], "lon": a["lon"], "tz": a["tz"], "mine": c in ("EWR", "BNA"), "items": []})["items"].append(n)
            return self._send(200, {"at": NOW - 120, "airports": list(aps.values())})
        if path == "/api/alerts":
            return self._send(200, {"alerts": alerts})
        if path == "/api/backup/brief":
            return self._send(200, {"state": "synced", "last": NOW - 900})
        if path == "/api/backup":
            return self._send(200, {"configured": True, "connected": True, "folder": "Flight Tracker Flighty (Home Assistant)", "email": "eric", "last_backup": NOW - 900})
        if path == "/api/settings":
            return self._send(200, {"settings": [{"key": "watch_hours", "label": "Watch window", "help": "Hours before departure", "kind": "num", "min": 1, "max": 48, "value": 12}]})
        if path.startswith("/api/airport/") and path.endswith("/layout"):
            return self._send(200, json.loads('{"features":[{"k":"runway","ref":"04L/22R","g":[[40.68,-74.18],[40.70,-74.17]]},{"k":"taxiway","ref":"P","g":[[40.685,-74.178],[40.69,-74.172],[40.695,-74.17]]},{"k":"terminal","name":"Terminal C","g":[[40.69,-74.18],[40.692,-74.18],[40.692,-74.178],[40.69,-74.178]]},{"k":"gate","ref":"C71","g":[40.691,-74.179]}]}'))
        if path == "/api/push/key":
            return self._send(200, {"key": "BOz2pT1L5m3r7cW4sYbqZ8K9Jt1v0aR3h6dXuF2gNwYkQeP5iV7xC9mL4bA8sD6fG1hJ3kL5zX7cV9bN2mQ4wE0", "count": 0})
        if path.startswith("/api/surface/"):
            return self._send(200, {"targets": []})
        if path == "/api/places":
            return self._send(200, {"type": "FeatureCollection", "features": []})
        if path == "/api/artcc":
            return self._send(200, ARTCC_FAKE)
        if path == "/api/debug":
            return self._send(200, {"schedule": {"exists": True, "path": "/homeassistant/ics2gcal/feed.ics", "checked": NOW - 600, "events": 20, "count": 4, "legs": []},
                                    "config": {"notify": "notify.mobile_app_erics_iphone", "airline_icao": "UAL", "ingress": "/x", "viewer_port": 6081},
                                    "aeroapi": {"enabled": False}, "gemini": {"enabled": False}, "screenshots": {"count": 0, "bytes": 0, "keep_hours": 24},
                                    "worker": {"busy": False}, "version": "3.22.3", "fetches": []})
        if path == "/api/rules":
            return self._send(200, {"rules": []})
        if path.startswith("/api/"):
            return self._send(404, {"error": "nf"})
        p = os.path.join(WWW, os.path.basename(path))
        if os.path.isfile(p):
            ct = {".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png"}.get(os.path.splitext(p)[1], "application/octet-stream")
            return self._send(200, open(p, "rb").read(), ct)
        return self._send(404, {"error": "nf"})

    def do_POST(self):
        return self._send(200, {"ok": True})


_gdp = {"key": "EWR|gdp|1", "kind": "gdp", "airport": "EWR", "label": "Ground delay program", "detail": "avg 38 min, max 70 min", "reason": "volume",
        "end": NOW + 2 * H, "scope": ["ZLA","ZAU","ZLC","ZTL","ZDC","ZNY","ZHU","ZJX","ZFW","ZOB","ZDV","ZOA","ZSE","ZBW","ZMA","ZKC","ZME","ZID"],
        "impact": [{"who": "you", "from": "BNA", "center": "ZME", "hit": True}], "advisory": "https://www.fly.faa.gov/", "source": "FAA SWIM + NAS status"}
for _L in (leg1, full1):
    _L["nas"] = [_gdp, nas_ewr]
    _L["problems"] = [{"level": "warn", "text": "Delayed 40 min", "delay": True}, {"level": "warn", "text": "EWR: Ground delay program", "nas": True}]
_ft = dict(full1["flight"]); _tt = dict(_ft["times"])
_tt["out"] = T(NOW + 30 * M, NOW + 70 * M); _tt["off"] = T(NOW + 45 * M, NOW + 96 * M)
_tt["on"] = T(NOW + 3 * H, NOW + 3 * H + 40 * M); _tt["in"] = T(NOW + 3 * H + 5 * M, NOW + 3 * H + 43 * M)
_ft["times"] = _tt; _ft["swim"] = {"edct": {"at": NOW + 96 * M, "for": "EWR"}}
full1.update(flight=_ft, phase="scheduled", live=None, turn=102)
state["nas"] = [_gdp, nas_ewr]

_C = {"ZLA":(34,-117),"ZAU":(42,-88),"ZLC":(42,-113),"ZTL":(34,-84),"ZDC":(37.5,-78),"ZNY":(41,-75),"ZHU":(30,-95),"ZJX":(31,-82),
      "ZFW":(33,-97),"ZOB":(41.5,-82),"ZDV":(39,-105),"ZOA":(39,-121),"ZSE":(46,-120),"ZBW":(43.5,-72),"ZMA":(26,-81),"ZKC":(38.5,-96),
      "ZME":(35,-89),"ZID":(39,-85),"ZAB":(34,-108),"ZMP":(45,-95)}
ARTCC_FAKE = {}
for k,(la,lo) in _C.items():
    w = 3
    r = [[la-w/2,lo-w],[la-w/2,lo+w],[la+w/2,lo+w],[la+w/2,lo-w],[la-w/2,lo-w]]
    rings = [r]
    if k in ("ZOA","ZLA","ZSE"): rings.append([[la-8,lo-45],[la-8,lo-3],[la+6,lo-3],[la+6,lo-45],[la-8,lo-45]])  # oceanic
    ARTCC_FAKE[k] = {"name": k, "rings": rings}

for _i,(_d,_a) in enumerate([("SFO","SAN"),("ORD","EWR"),("EWR","MSY"),("EWR","TPA"),("EWR","MIA"),("EWR","PBI")]):
    legs.append(sched_leg(f"X{_i}", "UA19"+str(_i), _d, _a, s4 + _i*86400, i4 + _i*86400))

ThreadingHTTPServer(("127.0.0.1", PORT), H_).serve_forever()
