// Tests für die deriveState-Logik (aus plugin.js extrahiert, in-repo).
// Lauf: node tests/test_derive.mjs
import fs from 'node:fs'
import assert from 'node:assert'

const src = fs.readFileSync(new URL('../plugin/plugin.js', import.meta.url), 'utf8')
  .replace(/import \{ jsx \} from 'react\/jsx-runtime'/, '')
  .replace(/import \{ useEffect, useRef \} from 'react'/, '')
  .replace(/import \{ useValue, host \} from '@hermes\/plugin-sdk'/, '')

// deriveState aus dem Source extrahieren (Funktionsrumpf)
const m = src.match(/function deriveState\(gateway, busy, awaiting\) \{([\s\S]*?)\n\}/)
assert.ok(m, 'deriveState nicht gefunden')
const deriveState = new Function('gateway', 'busy', 'awaiting', m[1])

const D = deriveState
// Gateway verbunden (ConnectionState 'open' — NICHT 'connected'!)
assert.equal(D('open', false, false), 'breathing', 'open + idle → breathing')
assert.equal(D('open', true, false), 'working', 'open + busy → working')
assert.equal(D('open', false, true), 'listening', 'open + awaiting → listening')
// Gateway-Zustände
assert.equal(D('connecting', false, false), 'connecting', 'connecting → connecting')
assert.equal(D('closed', true, false), 'connecting', 'closed überschreibt busy')
assert.equal(D('error', false, false), 'connecting', 'error → connecting')
// Kompatibilität: ältere Werte
assert.equal(D('connected', true, false), 'working', 'connected (alt) → working')
assert.equal(D('online', true, false), 'working', 'online (alt) → working')
// Nicht-String gateway (Objekt/undefined) → kein connecting
assert.equal(D(undefined, false, false), 'breathing')
assert.equal(D(null, true, false), 'working')
assert.equal(D({ id: 'x' }, false, false), 'breathing')

console.log('deriveState: alle Assertions OK')
