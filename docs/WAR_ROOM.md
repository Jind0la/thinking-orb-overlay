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

- [ ] Swift-App: Fenster + Engine-Port + Polling + Menü (in Arbeit — Era)
- [ ] Plugin-Backend `/status` (127.0.0.1:8799) + JS-Chip meldet Status
- [ ] Build + Start + Verifikation (Vision-Check des schwebenden Orbs)
- [ ] Push GitHub (Branch `feat/overlay-app`)

## Gaps / Bekannte Grenzen

- Status-Bridge lebt im Hermes-serve-Prozess → App ohne laufende Desktop-App
  bekommt keinen Status (gewollt: „an Hermes gebunden passt schon").
- Durchklick-Modus (ignoresMouseEvents) + Bewegen im selben Modus = Konflikt;
  v1: Toggle im Menü, Bewegen nur bei „interaktiv".
