"""Tests für die thinking-orb Status-Bridge (plugin_api.py).

Lauf:  uv run --with "pytest httpx fastapi" pytest tests/ -q
Hinweis: Der Modul-Import startet den Loopback-Thread (Import-Side-Effect,
bewusst). Im Testkontext ist der Port 8799 evtl. vom echten Backend belegt —
der Thread scheitert dann still (Bind-Fehler-Log). Die Route-Tests setzen
_bound gezielt; eine Autouse-Fixture isoliert _state/_seq/_bound zwischen
den Tests (Definitionsreihenfolge-unabhängig).
"""
import json
import sys
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "plugin" / "dashboard"))
import plugin_api  # noqa: E402

_app = FastAPI()
_app.include_router(plugin_api.router)
client = TestClient(_app)


@pytest.fixture(autouse=True)
def isolated_backend_state():
    """Jeder Test startet mit bekanntem Zustand — keine Reihenfolge-Lotterie."""
    with plugin_api._lock:
        plugin_api._state = {"state": "breathing", "seq": 0, "mood": "calm", "mood_set_at": 0.0, "attention": 0}
        plugin_api._bound = True
    yield
    with plugin_api._lock:
        plugin_api._state = {"state": "breathing", "seq": 0, "mood": "calm", "mood_set_at": 0.0, "attention": 0}
        plugin_api._bound = True


def test_report_valid_state():
    r = client.post("/report", json={"state": "working", "seq": 1})
    assert r.status_code == 200
    assert r.json() == {"ok": True}
    with plugin_api._lock:
        assert plugin_api._state["state"] == "working"
        assert plugin_api._state["seq"] == 1


def test_report_invalid_state_rejected():
    r = client.post("/report", json={"state": "dancing", "seq": 2})
    assert r.status_code == 400
    assert r.json() == {"ok": False}
    with plugin_api._lock:
        assert plugin_api._state["state"] == "breathing"  # unverändert


def test_report_invalid_json_rejected():
    r = client.post("/report", data="kein json", headers={"Content-Type": "application/json"})
    assert r.status_code == 400
    assert r.json() == {"ok": False}


def test_report_stale_seq_is_hard_503():
    """Out-of-Order: ältere seq → hart 503 (Vertrag AGENTS.md), State bleibt."""
    with plugin_api._lock:
        plugin_api._state["state"] = "breathing"
        plugin_api._state["seq"] = 10
    r = client.post("/report", json={"state": "working", "seq": 5})
    assert r.status_code == 503
    assert r.json() == {"ok": False, "error": "stale"}
    with plugin_api._lock:
        assert plugin_api._state["state"] == "breathing"


def test_report_without_seq_compat_window():
    """Alte Chips ohne seq: nur solange nie eine seq gesehen wurde."""
    r = client.post("/report", json={"state": "connecting"})
    assert r.status_code == 200
    assert r.json() == {"ok": True}
    # Sobald eine seq da ist, darf ein seq-loser Report den Guard nicht brechen
    client.post("/report", json={"state": "working", "seq": 1})
    r = client.post("/report", json={"state": "breathing"})
    assert r.status_code == 503
    assert r.json() == {"ok": False, "error": "stale"}


def test_report_503_when_not_bound():
    """Bind-Fail muss HART 503 sein — kein stilles Lügen."""
    plugin_api._bound = False
    r = client.post("/report", json={"state": "working", "seq": 99})
    assert r.status_code == 503
    assert r.json() == {"ok": False, "error": "loopback not bound"}


def test_loopback_get_path_restriction():
    """GET-Pfadprüfung gegen einen echten ephemeren Server (Port 0):
    /status → 200, alles andere → 404, Query-String leakt keinen Status."""
    server = ThreadingHTTPServer(("127.0.0.1", 0), plugin_api._Handler)
    port = server.server_address[1]
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    try:
        base = f"http://127.0.0.1:{port}"
        with urllib.request.urlopen(f"{base}/status", timeout=3) as resp:
            assert resp.status == 200
            import json
            assert json.loads(resp.read())["state"] == plugin_api._state["state"]
        # andere Pfade → 404
        for path in ("/whatever", "/status/", "/status?x=1"):
            try:
                urllib.request.urlopen(f"{base}{path}", timeout=3)
                raise AssertionError(f"{path} hätte 404 geben müssen")
            except urllib.error.HTTPError as e:
                assert e.code == 404, f"{path} → {e.code}"
    finally:
        server.shutdown()
        server.server_close()


# --- Mood-Dimension (2026-08-19) ---


def _mood_server():
    """Ephemerer Loopback-Server mit dem echten _Handler (POST /mood)."""
    server = ThreadingHTTPServer(("127.0.0.1", 0), plugin_api._Handler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    return server, f"http://127.0.0.1:{server.server_address[1]}"


def _post(base, path, payload):
    req = urllib.request.Request(
        f"{base}{path}", data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        # send_error liefert HTML-Body — nur JSON parsen, wenn es eines ist
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}


def test_mood_set_and_status_includes_mood():
    server, base = _mood_server()
    try:
        # Status enthält mood (Default calm)
        with urllib.request.urlopen(f"{base}/status", timeout=3) as resp:
            assert json.loads(resp.read()) == {"state": "breathing", "mood": "calm", "attention": 0}
        code, body = _post(base, "/mood", {"mood": "shy"})
        assert code == 200 and body == {"ok": True}
        with urllib.request.urlopen(f"{base}/status", timeout=3) as resp:
            assert json.loads(resp.read()) == {"state": "breathing", "mood": "shy", "attention": 0}
    finally:
        server.shutdown()
        server.server_close()


def test_mood_unknown_rejected():
    server, base = _mood_server()
    try:
        code, body = _post(base, "/mood", {"mood": "dancing"})
        assert code == 400 and body == {"ok": False}
        with plugin_api._lock:
            assert plugin_api._state["mood"] == "calm"  # unverändert
    finally:
        server.shutdown()
        server.server_close()


def test_mood_bad_payload_rejected():
    server, base = _mood_server()
    try:
        req = urllib.request.Request(f"{base}/mood", data=b"kein json",
                                     method="POST")
        try:
            urllib.request.urlopen(req, timeout=3)
            raise AssertionError("hätte 400 geben müssen")
        except urllib.error.HTTPError as e:
            assert e.code == 400
    finally:
        server.shutdown()
        server.server_close()


def test_state_report_leaves_mood_untouched():
    """/report (Chip) fasst mood nie an — nur /mood ändert die Stimmung."""
    server, base = _mood_server()
    try:
        _post(base, "/mood", {"mood": "aroused"})
        r = client.post("/report", json={"state": "working", "seq": 1})
        assert r.status_code == 200
        with plugin_api._lock:
            assert plugin_api._state["mood"] == "aroused"
            assert plugin_api._state["state"] == "working"
    finally:
        server.shutdown()
        server.server_close()


def test_mood_wrong_path_404():
    """POST nur auf exakt /mood — /status und Fremdpfade bleiben dicht."""
    server, base = _mood_server()
    try:
        for path in ("/status", "/mood/", "/mood?x=1", "/whatever"):
            code, _ = _post(base, path, {"mood": "shy"})
            assert code == 404, f"{path} → {code}"
        with plugin_api._lock:
            assert plugin_api._state["mood"] == "calm"
    finally:
        server.shutdown()
        server.server_close()


# --- Mood-Abklingen (Timeout, 2026-08-19) ---


def test_mood_decays_after_timeout():
    """Timeout abgelaufen → /status liefert calm (Orb fällt von selbst zurück)."""
    server, base = _mood_server()
    try:
        import time as _t
        with plugin_api._lock:
            plugin_api._state["mood"] = "shy"
            plugin_api._state["mood_set_at"] = _t.time() - plugin_api._MOOD_TIMEOUTS["shy"] - 10
        with urllib.request.urlopen(f"{base}/status", timeout=3) as resp:
            assert json.loads(resp.read()) == {"state": "breathing", "mood": "calm", "attention": 0}
    finally:
        server.shutdown()
        server.server_close()


def test_mood_keeps_within_timeout():
    """Innerhalb des Timeouts bleibt der Mood stehen."""
    server, base = _mood_server()
    try:
        import time as _t
        with plugin_api._lock:
            plugin_api._state["mood"] = "joyful"
            plugin_api._state["mood_set_at"] = _t.time() - 60  # 12min-Timeout, 1min alt
        with urllib.request.urlopen(f"{base}/status", timeout=3) as resp:
            assert json.loads(resp.read()) == {"state": "breathing", "mood": "joyful", "attention": 0}
    finally:
        server.shutdown()
        server.server_close()


def test_mood_repost_refreshes_timer():
    """Erneutes Setzen frischt den Timer auf — Emotion hält, solange genährt."""
    server, base = _mood_server()
    try:
        import time as _t
        with plugin_api._lock:
            plugin_api._state["mood"] = "aroused"
            plugin_api._state["mood_set_at"] = _t.time() - plugin_api._MOOD_TIMEOUTS["aroused"] + 5
        # Fast abgelaufen — ein neuer POST resetet
        code, _ = _post(base, "/mood", {"mood": "aroused"})
        assert code == 200
        with urllib.request.urlopen(f"{base}/status", timeout=3) as resp:
            assert json.loads(resp.read()) == {"state": "breathing", "mood": "aroused", "attention": 0}
    finally:
        server.shutdown()
        server.server_close()


def test_calm_has_no_timeout():
    """calm ist der Grundzustand — kein Timeout, bleibt stabil."""
    server, base = _mood_server()
    try:
        import time as _t
        with plugin_api._lock:
            plugin_api._state["mood"] = "calm"
            plugin_api._state["mood_set_at"] = _t.time() - 99999
        with urllib.request.urlopen(f"{base}/status", timeout=3) as resp:
            assert json.loads(resp.read()) == {"state": "breathing", "mood": "calm", "attention": 0}
    finally:
        server.shutdown()
        server.server_close()


# --- Attention-Signal (Antwort final geschrieben, 2026-08-19) ---


def test_report_with_attention_reaches_status():
    """attention aus /report landet im /status — die App pulst nur bei Änderung."""
    r = client.post("/report", json={"state": "breathing", "seq": 1, "attention": 1234567890123})
    assert r.status_code == 200
    with plugin_api._lock:
        assert plugin_api._state["attention"] == 1234567890123
    server, base = _mood_server()
    try:
        with urllib.request.urlopen(f"{base}/status", timeout=3) as resp:
            assert json.loads(resp.read())["attention"] == 1234567890123
    finally:
        server.shutdown()
        server.server_close()


def test_report_without_attention_keeps_last():
    """Heartbeat-/State-Reports ohne attention lassen den letzten Wert bestehen."""
    client.post("/report", json={"state": "working", "seq": 1, "attention": 42})
    r = client.post("/report", json={"state": "breathing", "seq": 2})
    assert r.status_code == 200
    with plugin_api._lock:
        assert plugin_api._state["attention"] == 42


def test_report_nonpositive_attention_ignored():
    """0/negatives attention ist kein Signal — wird nie übernommen."""
    client.post("/report", json={"state": "working", "seq": 1, "attention": 0})
    with plugin_api._lock:
        assert plugin_api._state["attention"] == 0
    client.post("/report", json={"state": "breathing", "seq": 2, "attention": -5})
    with plugin_api._lock:
        assert plugin_api._state["attention"] == 0


def test_report_bool_attention_ignored():
    """bool ist kein attention-Signal (Review-Minor #5) — True ist
    int-Subclass und würde sonst als 1 durchrutschen."""
    client.post("/report", json={"state": "breathing", "seq": 1, "attention": True})
    with plugin_api._lock:
        assert plugin_api._state["attention"] == 0


def test_stale_report_does_not_touch_attention():
    """Out-of-Order-Report (503) darf attention nicht überschreiben."""
    client.post("/report", json={"state": "breathing", "seq": 10, "attention": 99})
    r = client.post("/report", json={"state": "working", "seq": 5, "attention": 777})
    assert r.status_code == 503
    with plugin_api._lock:
        assert plugin_api._state["attention"] == 99
