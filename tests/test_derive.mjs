// Tests für die deriveState-Logik (aus plugin.js extrahiert, in-repo).
// Lauf: node tests/test_derive.mjs
import fs from 'node:fs'
import assert from 'node:assert'

const src = fs.readFileSync(new URL('../plugin/plugin.js', import.meta.url), 'utf8')
  .replace(/import \{ jsx \} from 'react\/jsx-runtime'/, '')
  .replace(/import \{ useEffect, useRef, useState \} from 'react'/, '')
  .replace(/import \{ useValue, host \} from '@hermes\/plugin-sdk'/, '')

// deriveState aus dem Source extrahieren (generischer Parameter-Match)
const m = src.match(/function deriveState\(([^)]*)\) \{([\s\S]*?)\n\}/)
assert.ok(m, 'deriveState nicht gefunden')
const deriveState = new Function(...m[1].split(',').map(s => s.trim()), m[2])

const P = (tools = 0, reasoning = false, streaming = false, waiting = false) => ({ tools, reasoning, streaming, waiting })
const D = deriveState

// Gateway verbunden (ConnectionState 'open' — NICHT 'connected'!)
assert.equal(D('open', false, false, P()), 'breathing', 'open + idle → breathing')
assert.equal(D('open', true, false, P()), 'working', 'open + busy → working')
assert.equal(D('open', false, true, P()), 'listening', 'open + awaiting → listening')

// Live-Phasen: Tools / Reasoning / Streaming
assert.equal(D('open', true, false, P(1)), 'searching', 'Tool läuft → searching')
assert.equal(D('open', true, false, P(0, true)), 'solving', 'Reasoning → solving')
assert.equal(D('open', true, false, P(0, false, true)), 'composing', 'Streaming → composing')
assert.equal(D('open', true, false, P(3, true, true)), 'composing', 'Streaming schlägt Reasoning/Tools')

// Warten auf Freigabe (nicht busy)
assert.equal(D('open', false, false, P(0, false, false, true)), 'listening', 'clarify/approval → listening')
assert.equal(D('open', false, true, P(0, false, false, true)), 'listening', 'waiting schlägt awaiting')

// Gateway-Zustände
assert.equal(D('connecting', false, false, P()), 'connecting', 'connecting → connecting')
assert.equal(D('closed', true, false, P()), 'connecting', 'closed überschreibt busy')
assert.equal(D('error', false, false, P()), 'connecting', 'error → connecting')

// Kompatibilität: ältere Werte
assert.equal(D('connected', true, false, P()), 'working', 'connected (alt) → working')
assert.equal(D('online', true, false, P()), 'working', 'online (alt) → working')

// Nicht-String gateway (Objekt/undefined) → kein connecting
assert.equal(D(undefined, false, false, P()), 'breathing')
assert.equal(D(null, true, false, P()), 'working')
assert.equal(D({ id: 'x' }, false, false, P()), 'breathing')

console.log('deriveState: alle Assertions OK')
