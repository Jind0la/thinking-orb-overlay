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
"""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

router = APIRouter()

_ALLOWED = {"working", "searching", "solving", "listening", "connecting",
            "weaving", "composing", "breathing", "shaping"}
_PORT = 8799

_state = {"state": "breathing", "seq": 0}
_lock = threading.Lock()
_bound = False
_httpd: ThreadingHTTPServer | None = None


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # NUR exakt /status — kein Trailing-Slash, kein Query-String (Leak-Frei)
        if self.path != "/status":
            self.send_error(404)
            return
        with _lock:
            body = json.dumps({"state": _state["state"]}).encode()
        self.send_response(200)
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
    return {"ok": True}
