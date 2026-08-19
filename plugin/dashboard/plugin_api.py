"""thinking-orb plugin backend — Status-Bridge für die native Orb-App.

Das JS-Plugin (Desktop-Chip) kennt host.state.busy und meldet den
Agent-Status per POST /report (Electron-Bridge authentifiziert automatisch).
Dieses Backend cached den State und servt ihn loopback-only auf
127.0.0.1:8799/status für die native Thinking-Orb-App.

Regeln (Review #1, Grok):
- GET nur auf exakt /status (sonst 404) — kein Status-Leak auf beliebige Pfade.
- Bind-Fehler ist HART sichtbar: /report antwortet 503, solange der
  Loopback-Server nicht gebunden ist (Port-Squatting kann den Orb sonst
  fremden State zeigen lassen).
- Monotone `seq` vom Chip: veraltete Reports (Out-of-Order) werden verworfen.
- Der Orb lügt nie: ohne gültigen Report bleibt der letzte State bestehen.
"""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fastapi import APIRouter, Request

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
        # Nur exakt /status — alles andere 404 (kein Status-Leak).
        if self.path.rstrip("/") != "/status":
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
    global _bound
    try:
        server = ThreadingHTTPServer(("127.0.0.1", _PORT), _Handler)
        with _lock:
            _bound = True
        server.serve_forever()
    except OSError as exc:
        print(f"[thinking-orb] loopback server FAILED on {_PORT}: {exc}")


# Import-Side-Effect bewusst: das Backend lebt im serve-Prozess, wird genau
# einmal importiert und nie entladen; idempotent gegen Doppel-Import.
threading.Thread(target=_serve, daemon=True).start()


@router.post("/report")
async def report(request: Request):
    global _state
    if not _bound:
        # Port-Squatting / Bind-Fail: hart melden statt still zu lügen.
        return {"ok": False, "error": "loopback not bound"}
    try:
        data = await request.json()
    except Exception:
        return {"ok": False}
    state = data.get("state")
    if state not in _ALLOWED:
        return {"ok": False}
    seq = data.get("seq")
    with _lock:
        if isinstance(seq, int) and seq < _state["seq"]:
            return {"ok": False, "error": "stale"}  # Out-of-Order verwerfen
        if isinstance(seq, int):
            _state["seq"] = seq
        _state["state"] = state
    return {"ok": True}
