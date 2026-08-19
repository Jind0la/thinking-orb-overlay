# Thinking Orb Overlay — Projektkontext

Native macOS-App: schwebender Agent-Status-Orb (3D-Partikel-Engine, Port von
thinking-orbs) über dem Desktop, live gekoppelt an den Hermes-Agent-Status
(Chip → Plugin-Backend → 127.0.0.1:8799 → App). An Hermes gebunden = gewollt.

Stack: Swift (Cocoa/CoreGraphics, kein Xcode-Projekt — `native/build-app.sh`)
+ Hermes-Desktop-Plugin (`plugin/`).

## Struktur

- `native/thinking-orb-app.swift` — App: borderless Floating-Fenster, Engine,
  State-Morphing (0,8 s Smoothstep), Poller (in-Flight-Guard), Menübar-Icon
- `native/build-app.sh` — Compile (universal) + Bundle + Signing
- `native/thinking-orb.sh` — Start/Stop
- `plugin/dashboard/plugin_api.py` — Backend: /report (seq-Guard) + Loopback
  127.0.0.1:8799/status (nur /status, hartes Bind-Flag)
- `plugin/plugin.js` — Statusbar-Chip: host.state → /report (monotone seq)
- `tests/` — pytest (Backend) + node (deriveState-Mapping)

## Tooling

- Build: `./native/build-app.sh` (Zertifikat „Agent Screen Dev")
- Backend-Tests: `uv run --with "pytest,httpx,fastapi" pytest tests/ -q`
- Derive-Tests: `node tests/test_derive.mjs`
- Start: `./native/thinking-orb.sh` / Stop: `./native/thinking-orb.sh stop`

## Verbindliche Regeln (Eigentümer)

- **Der Orb lügt nie:** bei Verbindungsfehler letzten State behalten; Backend
  verweigert Stale-seq und nicht-gebundenen Port hart (503).
- Fenster: rahmenlos, transparent, kein Focus-Steal (`orderFrontRegardless`),
  Escape-Hatch über Menübar-Icon (Durchklick-Toggle ist sonst Lockout).
- Manueller State im Menü pinnt; „Live folgen" gibt an den Poller zurück.

## Agent-Zusammenarbeit (verbindlich)

- War-Room (`docs/WAR_ROOM.md`) lesen vor Arbeit, aktualisieren danach;
  unter ~150 Zeilen halten.
- Zwischenstands-Pflicht bei >5 Tool-Calls.
- Cross-Review (anderer Provider) vor Merge auf main; Merge nur mit Nimars OK.
- Commit mit `Co-authored-by:`-Trailer; Feature-Branch → Push → Merge,
  nie direkt auf main. Push mit x-access-token-URL.
- Plugin-Installationen (~/.hermes/plugins + desktop-plugins) sind Kopien —
  Repo (`plugin/`) ist die Quelle, Fixes dort und zurückspiegeln.
