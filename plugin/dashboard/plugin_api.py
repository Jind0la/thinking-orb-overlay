"""thinking-orb plugin backend — Status-Bridge für die native Orb-App.

Das JS-Plugin (Desktop-Chip) kennt host.state.busy und meldet den
Agent-Status per POST /report (Electron-Bridge authentifiziert automatisch).
Dieses Backend cached den State und servt ihn loopback-only auf
127.0.0.1:8799/status für die native Thinking-Orb-App (kein Auth nötig —
nur Loopback, gleiches Muster wie der MJPEG-Stream auf 8788).

Der Orb lügt nie: Fehlt die Verbindung, behält die App ihren letzten State.
"""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fastapi import APIRouter, Request

router = APIRouter()

_ALLOWED = {"working", "searching", "solving", "listening", "connecting",
            "weaving", "composing", "breathing", "shaping"}
_PORT = 8799

_state = {"state": "breathing"}
_lock = threading.Lock()


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with _lock:
            body = json.dumps(_state).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # stiller Loopback — kein Log-Spam
        pass


def _serve() -> None:
    try:
        ThreadingHTTPServer(("127.0.0.1", _PORT), _Handler).serve_forever()
    except OSError as exc:
        print(f"[thinking-orb] loopback server failed: {exc}")


threading.Thread(target=_serve, daemon=True).start()


@router.post("/report")
async def report(request: Request):
    try:
        data = await request.json()
    except Exception:
        return {"ok": False}
    state = data.get("state")
    if state in _ALLOWED:
        with _lock:
            _state["state"] = state
        return {"ok": True}
    return {"ok": False}
