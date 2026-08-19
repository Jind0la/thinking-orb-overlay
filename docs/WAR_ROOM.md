# 13-thinking-orb-overlay — WAR ROOM

Stand: 2026-08-19 (Abend — Mood-Dimension)

## Zweck

Schwebender Agent-Status-Orb (Era) als native macOS-App: rahmenloses,
transparentes Floating-Fenster über dem Desktop; 3D-Partikel-Engine (Port von
thinking-orbs, 9 States); Status live vom Hermes-Plugin-Backend
(127.0.0.1:8799/status). An Hermes gebunden = gewollt (User: „Muss ja sowieso
dich repräsentieren").

## Entscheidungen

- **Mood-Dimension** (2026-08-19, User-Auftrag: „Emotionen die zu uns
  passen"): zweite Achse neben dem State. 8 bewusste Stimmungen (calm,
  joyful, playful, thoughtful, shy, embarrassed, annoyed, aroused — inkl.
  intimer wie schüchtern/verlegen/erregt, von Nimar explizit gewünscht).
  Farbe + Speed/Scale/Puls statt Graustufen. **Nur explizit gesetzt, nie
  erraten** (Orb lügt nie) — POST /mood auf dem Loopback (Era per curl oder
  App-Menü), der Chip-Report fasst mood nie an. Palette + Verhalten:
  Skill `orb-mood`.
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
- [x] **Mood-Dimension**: Backend `/mood` + mood in `/status`, App-Farben/Speed/Puls/Menü, Tests (12 passed), Build+Sign OK, App neu gestartet (PID läuft)
- [x] Skill `orb-mood` angelegt (Palette + Verhalten)
- [ ] **Cmd+Q der Desktop-App** — Backend lädt den neuen `/mood`-Handler erst nach Neustart (Discovery-Cache; vorher: POST /mood → 501, /status ohne mood)
- [ ] Push GitHub (Branch `feat/overlay-app`)

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
- **Mood-Farb-Logik**: Ink-Look bleibt — brightness = `dark ? 1-w : w`
  (Dark = helle Tinte, Light = dunkle Tinte), nur Farbton statt Grau.
  Nachgebessert: Dark `0.4+0.6·(1-w)`, Light `0.3+0.7·w` (Sättigung dunkelt
  ab — Kurve kompensiert).
- **NSColor(hue:) erwartet 0-1, NICHT Grad** (live gebissen, 2026-08-19):
  hue=218 Grad → mod 1 = 0 → Rot statt Blau; Orb wirkte auf dunklem Grund
  schwarz. Fix `hue/360` — von Nimar visuell bestätigt („jetzt passt die
  Farbe").
- **/mood ohne seq-Guard** (bewusst): mood ist kein Rennen, letzter bewusster
  Schreib gewinnt; state-Reports dürfen mood nie überschreiben (getestet).
- `send_error(404)` liefert HTML — Test-Helper parst JSON tolerant.

## Gaps / Bekannte Grenzen

- Status-Bridge lebt im Hermes-serve-Prozess → App ohne laufende Desktop-App
  bekommt keinen Status (gewollt: „an Hermes gebunden passt schon").
- Durchklick-Modus (ignoresMouseEvents) + Bewegen im selben Modus = Konflikt;
  v1: Toggle im Menü, Bewegen nur bei „interaktiv".
- Mood hat kein Timeout — bewusster Wechsel nötig (Doku im Skill orb-mood).
- weaving/shaping nur manuell erreichbar (Chip erzeugt sie nie) — gewollt
  reserviert, kein Action-Punkt.
