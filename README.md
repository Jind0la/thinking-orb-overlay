# Thinking Orb Overlay — Projektkontext

Native macOS-App: ein schwebender, rahmenloser Agent-Status-Orb (3D-Partikel-
Engine, Port von jakubantalik/thinking-orbs) über dem Desktop, live gekoppelt
an den Hermes-Agent-Status (busy → working, Leerlauf → breathing).

Stack: Swift (Cocoa, CoreGraphics), kein Xcode-Projekt — Build via `build-app.sh`
(swiftc). Status-Bridge: Hermes-Plugin-Backend auf 127.0.0.1.

## Struktur

- `native/thinking-orb-app.swift` — die App (Fenster, Engine, Polling, Menü)
- `native/build-app.sh` — Compile + Bundle + Signing (Vorlage: agent-screen)
- `plugin/` — Hermes-Plugin (Backend `/status`-Bridge + JS-Chip-Meldung)

## Tooling

- Build: `./native/build-app.sh` (swiftc -O, Bundle, Signing „Agent Screen Dev")
- Check: `./native/build-app.sh --check`
- Start: `./native/thinking-orb.sh`

## Verbindliche Regeln (Eigentümer)

- Der Orb repräsentiert Era — er lügt nie über den Agent-Status.
- Fenster: rahmenlos, transparent, keine Titelbar, `orderFrontRegardless`
  (kein Focus-Steal), frei verschiebbar, optional durchklickbar.

## Agent-Zusammenarbeit (verbindlich)

Siehe Template-Regeln: War-Room lesen/aktualisieren, Zwischenstands-Pflicht,
Cross-Review vor Merge, ehrliche Gap-Liste, `Co-authored-by:`-Trailer.
Git: Feature-Branch → Push → Merge, nie direkt auf main. Push mit
x-access-token-URL (Bearer wird abgelehnt).
