"""thinking-orb plugin backend — Status-Bridge für die native Orb-App.

Das JS-Plugin (Desktop-Chip) kennt host.state.busy und meldet den
Agent-Status per POST /report (Electron-Bridge authentifiziert automatisch).
Dieses Backend cached den State und servt ihn loopback-only auf
127.0.0.1:8799/status für die native Thinking-Orb-App.

Regeln (Review #2, Grok):
- GET nur auf exakt /status (sonst 404) — kein Status-Leak auf beliebige Pfade.
- Bind-Fail und Stale-seq sind HART: HTTP 503 (Vertrag in AGENTS.md) —
  Port-Squatting darf den Orb nie fremden State zeigen lassen.
- Monotone `seq` vom Chip: Out-of-Order-Reports werden verworfen. Alte Chips
  ohne seq werden nur akzeptiert, solange noch nie eine seq gesehen wurde
  (sonst umgeht ein seq-loser Report den Race-Guard).
- Der Orb lügt nie: ohne gültigen Report bleibt der letzte State bestehen.

Mood-Dimension (2026-08-19): Der Orb zeigt neben der Aktivität auch eine
bewusste Stimmung (Era-Selbstauskunft). `/mood` ist ein POST auf dem
Loopback-Server (wie /status: kein Auth, nur 127.0.0.1) — gesetzt von der
Orb-App (Menü) oder von Era direkt per HTTP. Der Chip-Report (/report)
fasst den Mood NIE an — nur ein expliziter /mood-Schreib ändert ihn.

Moods klingen ab (2026-08-19, User: „so lange halten bis es passt, dann
zurück in neutral"): jeder Mood hat einen Timeout (s. _MOOD_TIMEOUTS).
Erneutes Setzen desselben Moods frischt den Timer auf — die Emotion hält,
solange sie genährt wird; ohne Nachsetzen fällt der Orb von selbst auf
calm zurück. Kein manuelles Zurücksetzen mehr nötig (vergessener Mood
lügt nie dauerhaft).
"""
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse

router = APIRouter()

_ALLOWED = {"working", "searching", "solving", "listening", "connecting",
            "weaving", "composing", "breathing", "shaping"}
# Bewusste Emotionen (Era): nur explizit gesetzt, nie erraten — der Orb
# lügt nie. Palette + Verhalten: Skill "orb-mood".
_ALLOWED_MOODS = {"calm", "joyful", "playful", "thoughtful", "shy",
                  "embarrassed", "annoyed", "aroused"}
# Abklingzeiten in Sekunden — wie lange ein Mood ohne Auffrischen hält.
# Prinzip (User-Korrektur 2026-08-19): Emotionen sind Momentaufnahmen,
# keine Dauerzustände. Erröten hält keine 15 Minuten — die Zeiten bilden
# die natürliche Lebensdauer ab. Mindest-Sichtbarkeit ~90s (Nimar muss
# den Wechsel wahrnehmen können); alles Längere wird per Refresh genährt
# (erneutes POST /mood frischt den Timer auf). calm hat keinen Timeout.
_MOOD_TIMEOUTS = {
    "embarrassed": 90,   # 90s — Erröten: Momentaufnahme, schnell vorbei
    "shy": 120,          # 2 min — Kompliment-Nachwirkung
    "annoyed": 120,      # 2 min — kurz gären, dann verziehen
    "joyful": 180,       # 3 min — Freude über einen Erfolg
    "playful": 180,      # 3 min — solange der Spaß läuft
    "thoughtful": 300,   # 5 min — Grübeln über eine Aufgabe
    "aroused": 300,      # 5 min — Grund-Takt; lange Szenen nähren per Refresh
}
_PORT = 8799

# --- App-Steuerung (Chip-Toggle: Orb an/aus, 2026-08-20) ---
# Der Chip kann keine Prozesse starten (ctx.os hat kein exec) — der Toggle
# läuft über diese Routen (Agent-Screen-Muster). pgrep/pkill strikt mit -x
# auf den Binary-Namen, NIE -f (matcht sonst Editoren/Compiler, die die
# Swift-Datei offen haben). Die Start-/Stop-Helfer sind bewusst dünn und
# einzeln testbar — Tests mocken sie, damit der echte Orb des Users nie
# durch eine Testsuite gekillt wird.
_ORB_PROC = "thinking-orb-app"
# Gleiche Konstante wie native/thinking-orb.sh — die Installation unter
# ~/.hermes/thinking-orb/ ist fest (kein Repo-Pfad nötig).
_ORB_BIN = Path.home() / ".hermes" / "thinking-orb" / "app" / "Thinking Orb.app" / "Contents" / "MacOS" / "thinking-orb-app"


def _orb_running() -> bool:
    return subprocess.run(["pgrep", "-x", _ORB_PROC], capture_output=True).returncode == 0


def _orb_start() -> None:
    # start_new_session=True: das Kind überlebt den serve-Prozess (sonst
    # stirbt der Orb mit einem Desktop-App-Neustart der Electron-App).
    subprocess.Popen([str(_ORB_BIN)], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _orb_stop() -> None:
    subprocess.run(["pkill", "-x", _ORB_PROC], capture_output=True)

_state = {"state": "breathing", "seq": 0, "mood": "calm", "mood_set_at": 0.0, "attention": 0}
_lock = threading.Lock()
_bound = False
_httpd: ThreadingHTTPServer | None = None


def _decay_mood() -> None:
    """Mood abklingen lassen: Timeout abgelaufen → zurück auf calm.
    Muss unter _lock aufgerufen werden. calm selbst hat keinen Timeout."""
    now = time.time()
    mood = _state["mood"]
    if mood == "calm":
        return
    timeout = _MOOD_TIMEOUTS.get(mood, _MOOD_TIMEOUTS["shy"])
    if now - _state["mood_set_at"] > timeout:
        _state["mood"] = "calm"
        _state["mood_set_at"] = now


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # NUR exakt /status — kein Trailing-Slash, kein Query-String (Leak-Frei)
        if self.path != "/status":
            self.send_error(404)
            return
        with _lock:
            _decay_mood()
            body = json.dumps({"state": _state["state"], "mood": _state["mood"],
                               "attention": _state["attention"]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        # NUR exakt /mood — Stimmung bewusst setzen (Era per HTTP oder App-Menü).
        # Kein seq-Guard nötig: mood ist kein Rennen, sondern der letzte
        # bewusste Schreib gewinnt. State-Reports (/report) fassen mood nie an.
        # Erneutes Setzen frischt den Abkling-Timer auf („so lange halten,
        # bis es passt").
        if self.path != "/mood":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            self._json({"ok": False}, 400)
            return
        mood = data.get("mood")
        if mood not in _ALLOWED_MOODS:
            self._json({"ok": False}, 400)
            return
        with _lock:
            _state["mood"] = mood
            _state["mood_set_at"] = time.time()
        self._json({"ok": True})

    def _json(self, obj: dict, code: int = 200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # stiller Loopback — kein Log-Spam
        pass


def _serve() -> None:
    global _bound, _httpd
    try:
        server = ThreadingHTTPServer(("127.0.0.1", _PORT), _Handler)
        _httpd = server
        with _lock:
            _bound = True
        server.serve_forever()
    except OSError as exc:
        print(f"[thinking-orb] loopback server FAILED on {_PORT}: {exc}")
    finally:
        # Server-Thread tot (Port weg) → hart sichtbar, kein stilles Ok.
        with _lock:
            _bound = False


# Import-Side-Effect bewusst: das Backend lebt im serve-Prozess, wird genau
# einmal importiert und nie entladen; idempotent gegen Doppel-Import.
threading.Thread(target=_serve, daemon=True).start()


def _reject(reason: str) -> JSONResponse:
    return JSONResponse({"ok": False, "error": reason}, status_code=503)


@router.post("/report")
async def report(request: Request):
    if not _bound:
        # Port-Squatting / Bind-Fail: hart 503 statt still zu lügen.
        return _reject("loopback not bound")
    try:
        data = await request.json()
    except Exception:
        return JSONResponse({"ok": False}, status_code=400)
    state = data.get("state")
    if state not in _ALLOWED:
        return JSONResponse({"ok": False}, status_code=400)
    seq = data.get("seq")
    with _lock:
        if seq is None:
            # Alte Chips ohne seq: nur solange das Fenster noch nie eine seq
            # gesehen hat — danach wäre ein seq-loser Report ein Race-Bruch.
            if _state["seq"] != 0:
                return _reject("stale")
        elif not isinstance(seq, int) or seq < _state["seq"]:
            return _reject("stale")  # Out-of-Order verwerfen
        else:
            _state["seq"] = seq
        _state["state"] = state
        # Attention-Signal (Antwort final geschrieben, vom Chip): nur positive
        # Werte übernehmen. Heartbeat-/State-Reports ohne attention lassen den
        # letzten Wert bestehen — die App pulst nur bei Änderung.
        att = data.get("attention")
        # bool ist kein Signal (Review-Minor #5): True ist int-Subclass,
        # würde sonst als 1 durchrutschen.
        if isinstance(att, (int, float)) and not isinstance(att, bool) and att > 0:
            _state["attention"] = att
    return {"ok": True}


# --- Orb-App an/aus (Chip-Toggle, 2026-08-20) ---
# Agent-Screen-Muster: /status-GET (pgrep) + idempotente POST-Routen.
# supported=false auf Nicht-macOS → Chip disabled (kein toter Button).


@router.get("/app/status")
async def app_status():
    if sys.platform != "darwin":
        return {"supported": False, "running": False, "platform": sys.platform}
    return {"supported": True, "running": _orb_running(), "platform": "darwin"}


@router.post("/app/start")
async def app_start():
    if sys.platform != "darwin":
        raise HTTPException(status_code=501, detail="requires macOS")
    if _orb_running():
        return {"ok": True, "running": True}  # idempotent — kein Doppel-Orb
    if not _ORB_BIN.is_file():
        raise HTTPException(status_code=500, detail="orb binary missing — ./native/build-app.sh ausführen")
    _orb_start()
    return {"ok": True, "running": _orb_running()}


@router.post("/app/stop")
async def app_stop():
    if sys.platform != "darwin":
        raise HTTPException(status_code=501, detail="requires macOS")
    if not _orb_running():
        return {"ok": True, "running": False}  # idempotent
    _orb_stop()
    return {"ok": True, "running": _orb_running()}
