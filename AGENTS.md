# <Projektname> — Projektkontext

Kurzbeschreibung: <Was ist das Projekt? Ein Satz.>
Stack: <z.B. React 18 + Vite + TypeScript, deutsch>

## Struktur

- <Wichtige Ordner und ihre Aufgabe>

## Tooling

- Build: <npm run build o.ä.>
- Dev: <npm run dev o.ä.>
- Checks: <tsc, lint, Tests>

## Verbindliche Regeln (Eigentümer)

<!-- Projektspezifische Regeln hier eintragen (Design, Architektur, Konventionen).
     Die globalen Design-Qualitätsregeln gelten automatisch
     (~/.cursor/rules/design-quality.mdc) — hier nur ERGÄNZENDES. -->

## Agent-Zusammenarbeit (verbindlich)

Dieses Projekt wird von mehreren Agenten bearbeitet (Hermes = Orchestratorin,
Cursor, Grok Build) und von einem Menschen (Nimar) gesteuert. Diese Regeln
gelten für jeden Agenten:

### War Room
- Projekt-Log: `docs/WAR_ROOM.md` — vor der Arbeit lesen (Kontext, laufende
  Tasks, Entscheidungen, bekannte Gaps), nach der Arbeit eigenen Teil
  aktualisieren.
- **Verdichtung:** Datei unter ~150 Zeilen halten. Abgeschlossene Tasks aus
  "Laufende Tasks" entfernen, alte Einträge (>2 Wochen) kürzen. Kein
  Session-Protokoll — Arbeitsgedächtnis.

### Zwischenstands-Pflicht
- Bei Tasks mit >5 Tool-Calls oder >2 Minuten Laufzeit: mindestens EIN
  Zwischenstand dokumentieren (was fertig ist, was als Nächstes kommt,
  offene Fragen), BEVOR das Endergebnis gemeldet wird. Menschen steuern
  die Arbeit live, nicht erst beim Ergebnis.

### Cross-Review
- Nichts mergen, ohne dass ein ANDERER Agent (anderer Provider) den Diff
  reviewt hat. Ein Modell, das die eigene Familie reviewt, wiederholt seine
  eigenen blinden Flecken.
- Review-Kriterien: Bugs, Security, Race Conditions, fehlende Tests,
  Design-Konformität.

### Ehrlichkeit (Known Limitations)
- Keine geschönten Erfolgsmeldungen. Was nicht funktioniert, wird als
  bekannte Lücke in die Gap-Liste im War Room eingetragen — mit Workaround
  oder Fix-Plan.

### Git-Identität
- Agent-Arbeit per `Co-authored-by:`-Trailer kennzeichnen:
  `Co-authored-by: Cursor <cursor@anysphere.com>` /
  `Co-authored-by: Grok Build <grok@x.ai>`.
- Autorenschaft bleibt getrennt: wer gebaut hat ≠ wer orchestriert hat.
