# 13-thinking-orb-overlay — WAR ROOM

Stand: 2026-08-20 (Chip-Toggle: Orb an/aus)

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
- **Moods klingen ab** (2026-08-19, User: „so lange halten bis es passt,
  dann zurück in neutral"): Timeout pro Mood, erneutes Setzen frischt den
  Timer auf. Kein manuelles Zurücksetzen nötig; Farbwechsel in der App
  morphen weich (0,8s Smoothstep, gleiche Kurve wie State-Morph).
  **Zeiten (User-Korrektur: „Erröten hält keine 15 Minuten!"):** Emotionen
  sind Momentaufnahmen — embarrassed 90s, shy/annoyed 2 min, joyful/playful
  3 min, thoughtful/aroused 5 min. Untergrenze = Sichtbarkeit (~90s);
  alles Längere wird per Refresh genährt.
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
- [x] **Mood-Dimension**: Backend `/mood` + mood in `/status`, App-Farben/Speed/Puls/Menü, Tests (12 passed), Build+Sign OK, App neu gestartet (PID läuft)
- [x] Skill `orb-mood` angelegt (Palette + Verhalten)
- [x] **Attention-Pulse** (2026-08-19): Chip meldet message.complete →
  Atem-Signal: Partikel atmen + Farbverlauf rotiert im Uhrzeigersinn
  (im Glow-Lab iteriert, User-Einstellungen übernommen; Tests 21 passed,
  Build+Sign OK, App läuft)
- [x] **GEMERGT auf main (2026-08-19, Abend)** — feat/attention-pulse via
  --no-ff (main hatte ac98d46 exklusiv). Cross-Review einmalig ausgesetzt
  (Grok-CLI 7× gescheitert, Nimar-OK); Minors #1/#3/#5 gefixt, #4
  dokumentiert. Cmd+Q der Desktop-App erledigt (Nimar), Backend-Kopie
  gespiegelt, main gepusht.
- [x] **Chip-Toggle** (2026-08-20, User: „keinen Button um die Orb an und aus
  zu schalten“): **Der Orb-Chip selbst ist der Toggle** — Klick auf den Chip
  startet/stoppt die native App (User-Korrektur: kein separater Power-Button).
  App aus = Chip gedimmt (opacity 0.45). Backend `/app/status` (pgrep -x),
  `/app/start`/`/app/stop` (idempotent, start_new_session, pkill -x — nie
  -f); Chip: useQuery 5s + useMutation mit FRISCH-Status
  (Agent-Screen-Muster). Tests 28 passed (7 neue), ESM-Check grün, Kopien
  gespiegelt.

## Erkenntnisse 2026-08-20 (Chip-Toggle)

- Backend braucht Cmd+Q, Chip Hot-Reload-fähig; User will KEINEN Power-
  Button — der Chip IST der Toggle (Dimmung, title nie). Path = `__slots__`:
  `_ORB_BIN` selbst patchen, nicht is_file.
- Loopback 8799 = nur /status+/mood; /app-Routen via Bridge (ctx.rest) —
  curl 8799 404 = normal.

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
- **Mood-Farb-Logik**: Ink-Look bleibt — brightness = `dark ? 1-w : w`
  (Dark = helle Tinte, Light = dunkle Tinte), nur Farbton statt Grau.
  Nachgebessert: Dark `0.4+0.6·(1-w)`, Light `0.3+0.7·w` (Sättigung dunkelt
  ab — Kurve kompensiert).
- **NSColor(hue:) erwartet 0-1, NICHT Grad** (live gebissen, 2026-08-19):
  hue=218 Grad → mod 1 = 0 → Rot statt Blau; Orb wirkte auf dunklem Grund
  schwarz. Fix `hue/360` — von Nimar visuell bestätigt („jetzt passt die
  Farbe").
- `/mood` ohne seq-Guard (bewusst): mood ist kein Rennen, letzter bewusster
  Schreib gewinnt; state-Reports dürfen mood nie überschreiben (getestet).
- **Backend-Änderung = Kopie spiegeln + Cmd+Q** (live gebissen 2026-08-19):
  `~/.hermes/plugins/thinking-orb/dashboard/plugin_api.py` ist eine KOPIE —
  nur Repo patchen reicht nicht, der serve-Prozess lädt die Kopie. Erst
  `cp plugin/dashboard/plugin_api.py ~/.hermes/plugins/...` (+ `__pycache__`
  löschen), DANN Cmd+Q. Symptom sonst: /status ohne mood, POST /mood 501.
- `send_error(404)` liefert HTML — Test-Helper parst JSON tolerant.

## Erkenntnisse 2026-08-19 (Attention-Pulse)

- Trigger: `message.complete` = Antwort final geschrieben. Der Chip hängt
  genau DIESEM Report einen einmaligen attention-Timestamp an
  (answerDone-Flag verbraucht sich); Heartbeat/State-Reports senden kein
  attention → Backend behält den letzten Wert → App pulst nur bei Änderung.
- App-Guard: Pulse nur wenn attention frisch (<8s) UND != letzter Wert —
  App-Start/Backend-Neustart lösen keinen Geister-Pulse aus.
- Effekt (Glow-Lab-iteriert bis User-OK, „So übernehmen“): Atem-Kurve
  rein -3.6×amp / raus +2.4×amp bei 15% Amplitude, 2,8s; Farbverlauf rotiert
  einmal (hue = Winkel - p·2π, Boost 0.12·env); Fenster 1.5× Orb mit
  transparentem Rand („Ränder der Box“ live gebissen). **Skalierung wirkt auf
  Position + Radius** (nur Radien = unsichtbar). Glow-Gradient verworfen
  (User: „zu platt“ — no-filters-Prinzip).
- Swift/CG-Pitfall: `ctx.save()`/`restore()` existieren nicht — es sind
  `saveGState()`/`restoreGState()` (Build-Fehler live gefixt).
- `/status` liefert attention erst nach Cmd+Q (Discovery-Cache) — der
  Live-Test ist die nächste final geschriebene Antwort.
- **GEMERGT auf main (2026-08-19, Abend)** — Cross-Review einmalig
  ausgesetzt (Grok-CLI 7× gescheitert — headless bricht reproduzierbar
  ohne Ergebnis ab; TUI hängt im Onboarding; Codex/Claude/tmux fehlen;
  kein zweites Hermes-Modell), Selbst-Review + Nimar-OK. Minors #1/#3/#5
  gefixt, #4 (Chip-Batch-Race) dokumentiert statt Fake-Fix.

## Gaps / Bekannte Grenzen

- Status-Bridge lebt im Hermes-serve-Prozess → App ohne laufende Desktop-App
  bekommt keinen Status (gewollt: „an Hermes gebunden passt schon").
- Durchklick-Modus (ignoresMouseEvents) + Bewegen im selben Modus = Konflikt;
  v1: Toggle im Menü, Bewegen nur bei „interaktiv".
- weaving/shaping nur manuell erreichbar (Chip erzeugt sie nie) — gewollt
  reserviert, kein Action-Punkt.
