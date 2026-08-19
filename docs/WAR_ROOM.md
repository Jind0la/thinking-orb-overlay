# 13-thinking-orb-overlay — WAR ROOM

Stand: 2026-08-19

## Zweck

Schwebender Agent-Status-Orb (Era) als native macOS-App: rahmenloses,
transparentes Floating-Fenster über dem Desktop; 3D-Partikel-Engine (Port von
thinking-orbs, 9 States); Status live vom Hermes-Plugin-Backend
(127.0.0.1:8799/status). An Hermes gebunden = gewollt (User: „Muss ja sowieso
dich repräsentieren").

## Entscheidungen

- **Pet-System verworfen** (2026-08-19): max. 6 Frames/State @ 1100ms ≈ 5,4 fps
  — der Orb lebt von 60fps-Partikelbewegung. Nur Overlay-App liefert „wirklich
  3D und flüssig". User-Go: „Ja mach!"
- **Status-Bridge:** JS-Plugin (Chip) meldet busy/awaitingResponse/gateway per
  POST an das neue Plugin-Backend; das Backend cached den Status und servt ihn
  auf `127.0.0.1:8799/status` (Loopback-only, kein Auth — wie MJPEG auf 8788).
- **Signing:** vorhandene Identität „Agent Screen Dev" (keine TCC-Rechte nötig,
  kein Screen-Recording; ad-hoc vermeiden).
- **Fenster:** `.borderless`, `backgroundColor = .clear`, `isOpaque = false`,
  `level = .floating`, `collectionBehavior = [.canJoinAllSpaces,
  .fullScreenAuxiliary]`, `isMovableByWindowBackground = true`,
  `orderFrontRegardless()` (kein Focus-Steal), `LSUIElement` (kein Dock-Icon).

## Laufende Tasks

- [x] Swift-App: Fenster + Engine-Port + Polling + Menü (gebaut, kompiliert, signiert, läuft — Orb sichtbar über Desktop, Vision-verifiziert)
- [x] Plugin-Backend `/status` (127.0.0.1:8799) + JS-Chip meldet Status (Code fertig, Harness grün)
- [x] **Live-Test bestanden**: `{"state":"working"}` während Agent busy — Kette läuft Ende-zu-Ende
- [x] Grok-Review Runde 1+2+3: Blocker+Majors abgearbeitet, Tests in-repo → **MERGE-READY**
- [x] **GEMERGT auf main + gepusht (2026-08-19)** — Branch feat/overlay-app ist die Feature-Historie
- [x] Live-Phasen (Gateway-Events), Pin-Indikator, seq-Reload-Lockout-Fix

## Erkenntnisse 2026-08-19 (Build-Lauf)

- Pet-Format verworfen (s. Entscheidungen); Overlay-App = der Weg.
- `let _ctx = null`-Deklaration NACH erstem Patch vergessen → Toast `_ctx is
  not defined` (Relikt, Harness beweist: Code grün). Hot-Reload lädt nach
  Load-Fehler offenbar nicht automatisch neu — App-Neustart nötig.
- Config-yaml-Write: Hermes-Parser blockt Inline-Edit; Lösung: Skript-Datei +
  `uv run --with pyyaml`. Backup `config.yaml.bak-thinking-orb`.
- Statusbar-Items sind AX-unsichtbar (auch „Voice aus" fehlt im Baum) —
  Chip-Nachweis nur über Harness/Vision/User-Blick.
- swiftc: Parameter `pow` schattiert globale pow() → umbenennen.
- **ConnectionState = 'idle'|'connecting'|'open'|'closed'|'error'** — der
  Gateway ist bei Verbindung `'open'`, NICHT 'connected'! Fehlender Check
  zeigte dauerhaft „connecting". Fix: `['open','connected','online']`.
- **seq-Reload-Lockout (Killer-Pitfall):** Modul-Globals (Plugin) starten bei
  jedem Reload bei 0 → Backend (seq-Guard) verwirft ALLE Reports als stale →
  Orb friert dauerhaft ein, Chip läuft live weiter („anderer State").
  Fix: Zähler-Start hoch (`Date.now() % 1e9`) + 5s-Heartbeat im Chip.
- Unified-Log-Debugging: NSLog wird als `<private>` redacted — `print()`
  (stderr) + App mit Log-Datei starten ist der verlässliche Debug-Weg.

## Gaps / Bekannte Grenzen

- Status-Bridge lebt im Hermes-serve-Prozess → App ohne laufende Desktop-App
  bekommt keinen Status (gewollt: „an Hermes gebunden passt schon").
- Durchklick-Modus (ignoresMouseEvents) + Bewegen im selben Modus = Konflikt;
  v1: Toggle im Menü, Bewegen nur bei „interaktiv".
