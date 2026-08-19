"""Tests für die thinking-orb Status-Bridge (plugin_api.py).

Lauf:  uv run --with "pytest httpx fastapi" pytest tests/ -q
Hinweis: Der Modul-Import startet den Loopback-Thread (Import-Side-Effect,
bewusst). Im Testkontext ist der Port 8799 evtl. vom echten Backend belegt —
der Thread scheitert dann still (Bind-Fehler-Log) und _bound bleibt False;
die Route-Tests setzen _bound gezielt, der 503-Fall wird explizit getestet.
"""
import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "plugin" / "dashboard"))
import plugin_api  # noqa: E402

# TestClient braucht eine echte App (Middleware-Stack), kein nacktes Router-Objekt
_app = FastAPI()
_app.include_router(plugin_api.router)
client = TestClient(_app)


def test_report_valid_state():
    plugin_api._bound = True
    r = client.post("/report", json={"state": "working", "seq": 1})
    assert r.status_code == 200
    assert r.json() == {"ok": True}
    with plugin_api._lock:
        assert plugin_api._state["state"] == "working"
        assert plugin_api._state["seq"] == 1


def test_report_invalid_state_rejected():
    plugin_api._bound = True
    r = client.post("/report", json={"state": "dancing", "seq": 2})
    assert r.json() == {"ok": False}
    with plugin_api._lock:
        assert plugin_api._state["state"] == "working"  # unverändert


def test_report_invalid_json_rejected():
    plugin_api._bound = True
    r = client.post("/report", data="kein json", headers={"Content-Type": "application/json"})
    assert r.json() == {"ok": False}


def test_report_stale_seq_dropped():
    """Out-of-Order: ältere seq darf den neueren State nicht überschreiben."""
    plugin_api._bound = True
    with plugin_api._lock:
        plugin_api._state["state"] = "breathing"
        plugin_api._state["seq"] = 10
    r = client.post("/report", json={"state": "working", "seq": 5})
    assert r.json() == {"ok": False, "error": "stale"}
    with plugin_api._lock:
        assert plugin_api._state["state"] == "breathing"


def test_report_without_seq_still_accepted():
    """Ohne seq (ältere Chips) weiter akzeptieren — sequenzlos ist kein
    Out-of-Order-Kriterium vorhanden, der Wert wird trotzdem übernommen."""
    plugin_api._bound = True
    r = client.post("/report", json={"state": "connecting"})
    assert r.json() == {"ok": True}
    with plugin_api._lock:
        assert plugin_api._state["state"] == "connecting"


def test_report_503_when_not_bound():
    """Bind-Fail muss HART sichtbar sein — kein stilles Lügen."""
    plugin_api._bound = False
    r = client.post("/report", json={"state": "working", "seq": 99})
    assert r.json() == {"ok": False, "error": "loopback not bound"}
    plugin_api._bound = True  # aufräumen für weitere Tests


# Die GET-Pfadprüfung (/status vs. 404 sonst) wird live verifiziert:
#   curl -s http://127.0.0.1:8799/status   → 200
#   curl -s http://127.0.0.1:8799/whatever → 404
