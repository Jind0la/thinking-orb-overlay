// thinking-orb-app.swift — schwebender Agent-Status-Orb für Hermes (Era).
//
// Fenster: rahmenlos, transparent, immer im Vordergrund, frei verschiebbar.
// Engine: 1:1-Port von jakubantalik/thinking-orbs (MIT) — 9 States, echte 3D-
// Punktewolken, Ink-Tiefenschattierung (Dark = gespiegelt). Siehe NOTICE.
// Status: pollt http://127.0.0.1:8799/status (Hermes-Plugin-Backend) — der
// Orb lügt nie: bei Verbindungsfehler bleibt der letzte State bestehen.
//
// Build: ./build-app.sh (nie ad-hoc signieren — Konsistenz mit Agent Screen).

import Cocoa

// MARK: - Engine (Port aus thinking-orbs/src/engine, MIT)

struct Dot {
    var x: Double, y: Double, z: Double, r: Double, white: Double, a: Double
}
struct Line {
    var x1: Double, y1: Double, x2: Double, y2: Double, white: Double, a: Double, w: Double
}
struct Frame { var dots: [Dot]; var lines: [Line] }

typealias Proj = (Double, Double, Double) -> (Double, Double, Double)

func hashD(_ a: Double, _ b: Double) -> Double {
    let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
    return h - floor(h)
}
func vnoise(_ x: Double, _ y: Double) -> Double {
    let xi = floor(x), yi = floor(y)
    var fx = x - xi, fy = y - yi
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    let a = hashD(xi, yi), b = hashD(xi + 1, yi), c = hashD(xi, yi + 1), d = hashD(xi + 1, yi + 1)
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
}
func fibDir(_ i: Int, _ n: Int) -> (Double, Double, Double) {
    let golden = Double.pi * (3 - sqrt(5))
    let y = 1 - (2 * (Double(i) + 0.5)) / Double(n)
    let rad = sqrt(1 - y * y)
    let a = Double(i) * golden
    return (rad * cos(a), y, rad * sin(a))
}
func angleDelta(_ a: Double, _ b: Double) -> Double {
    atan2(sin(a - b), cos(a - b))
}
func makeProj(_ yaw: Double, _ tilt: Double, _ cx: Double, _ cy: Double, _ scale: Double) -> Proj {
    let st = sin(tilt), ct = cos(tilt), sy = sin(yaw), cyw = cos(yaw)
    return { (x, y, z) in
        let x1 = x * cyw + z * sy
        let z1 = -x * sy + z * cyw
        let y1 = y * ct - z1 * st
        let z2 = y * st + z1 * ct
        return (cx + x1 * scale, cy - y1 * scale, z2)
    }
}
func radiusScale(_ size: Double, _ p: Double) -> Double { pow(size / 300.0, p) }
func frac(_ x: Double) -> Double { x - floor(x) }
func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }

func finalize(_ dots: [Dot], _ lines: [Line], _ rMin: Double = 0.3) -> Frame {
    var visible: [Dot] = []
    for var d in dots {
        if d.a < 0.02 { continue }
        d.r = max(rMin, d.r)
        visible.append(d)
    }
    visible.sort { $0.z < $1.z }
    return Frame(dots: visible, lines: lines.filter { $0.a >= 0.02 })
}

// Profile + Presets (64er-Tunings, wie das Inline-Widget)
func scaleCounts(_ o: [String: Double], _ scale: Double) -> [String: Double] {
    var out = o
    let rt = sqrt(scale)
    let pairs: [(String, String)] = [("latRings", "lonDensity"), ("rings", "lonDensity"), ("lanes", "segs")]
    var done = Set<String>()
    for (a, b) in pairs {
        if let va = out[a], let vb = out[b], !done.contains(a), !done.contains(b) {
            out[a] = Double(max(2, Int((va * rt).rounded())))
            out[b] = Double(max(2, Int((vb * rt).rounded())))
            done.insert(a); done.insert(b)
        }
    }
    let countKeys = ["orbitN", "ghostN", "nodeN", "strandN", "signals"]
    for k in countKeys {
        if let v = out[k], v != 0, !done.contains(k) { out[k] = Double(max(1, Int((v * scale).rounded()))) }
    }
    if let v = out["iconD"] { out["iconD"] = max(0.02, v * scale) }
    return out
}
func scaleRadii(_ o: [String: Double], _ scale: Double) -> [String: Double] {
    var out = o
    let radiusKeys = ["rBase", "rDepth", "rActive", "rDot", "ghostR", "partR", "partRDepth", "nodeR", "nodeRDepth"]
    for k in radiusKeys { if let v = out[k] { out[k] = v * scale } }
    out["rSizeMul"] = (out["rSizeMul"] ?? 1) * scale
    return out
}

let BASE_PROFILES: [String: [String: Double]] = [
    "globe":  ["latRings": 17, "lonDensity": 44, "rBase": 0.6, "rDepth": 1.7, "rBoost": 1.0, "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3],
    "orbits": ["orbitN": 12, "ghostN": 40, "ghostR": 0.9, "ghostA": 0.5, "particles": 3, "partR": 1.2, "partRDepth": 1.6, "rsPow": 0.6, "rMin": 0.3],
    "rubik":  ["latRings": 15, "lonDensity": 40, "moveCount": 14, "rBase": 0.6, "rDepth": 1.7, "rActive": 0.3, "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3],
    "wave":   ["rings": 15, "lonDensity": 40, "rBase": 0.6, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
    "web":    ["nodeN": 30, "thr": 0.72, "signals": 5, "nodeR": 1.4, "nodeRDepth": 1.8, "lineW": 0.8, "rsPow": 0.6, "rMin": 0.3],
    "braid":  ["strandN": 52, "turns": 3.0, "ghostN": 150, "rBase": 1.2, "rDepth": 1.8, "rsPow": 0.6, "rMin": 0.3],
    "ribbon": ["lanes": 5, "segs": 88, "ghostN": 150, "rBase": 1.1, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
    "ring":   ["lanes": 5, "segs": 88, "ghostN": 0, "faceOn": 1, "rBase": 1.1, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
    "morph":  ["rDot": 0.021, "iconD": 1, "rMin": 0.25]
]

let PRESETS: [String: (speed: Double, count: Double, size: Double, extra: [String: Double])] = [
    "orbits": (1.885, 1, 1, [:]),
    "globe":  (2.015, 0.42, 1.15, ["scanMul": 4.08, "dimBase": 0.45]),
    "rubik":  (1.82, 0.35, 1.05, [:]),
    "wave":   (4.388, 0.341, 1, [:]),
    "web":    (3.315, 1.35, 0.95, [:]),
    "braid":  (1.625, 0.5, 1, [:]),
    "ribbon": (2.34, 0.25, 0.85, ["spin": 0, "bandMul": 3.9, "wobMul": 1]),
    "ring":   (3.24, 0.25, 0.956, ["spin": 0, "bandMul": 3.627, "wobMul": 0.368]),
    "morph":  (2.405, 0.702, 0.395, ["spread": 1.45])
]

let STATE_TO_MODE: [String: String] = [
    "working": "orbits", "searching": "globe", "solving": "rubik", "listening": "wave",
    "connecting": "web", "weaving": "braid", "composing": "ribbon", "breathing": "ring", "shaping": "morph"
]

func resolvePreset(_ state: String) -> (mode: String, speed: Double, opts: [String: Double]) {
    let mode = STATE_TO_MODE[state] ?? "ring"
    let preset = PRESETS[mode]!
    var opts = BASE_PROFILES[mode]!
    if preset.count != 1 { opts = scaleCounts(opts, preset.count) }
    if preset.size != 1 { opts = scaleRadii(opts, preset.size) }
    for (k, v) in preset.extra { opts[k] = v }
    return (mode, preset.speed, opts)
}

// MARK: - Frames (1:1 Port)

func frameOrbits(_ size: Double, _ t: Double, _ o: [String: Double]) -> Frame {
    let cx = size / 2, cy = size / 2, R = (size / 2) * 0.82
    let pt = makeProj(t * 0.12, 0.3, cx, cy, 1)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    var dots: [Dot] = []
    let orbitN = Int(o["orbitN"] ?? 12), ghostN = Int(o["ghostN"] ?? 40), particles = Int(o["particles"] ?? 3)
    for orb in 0..<orbitN {
        let h1 = hashD(Double(orb), 1.7), h2 = hashD(Double(orb), 5.2), h3 = hashD(Double(orb), 8.9)
        let ro = R * (0.45 + 0.52 * h1)
        let th = h1 * 2 * Double.pi, phi = acos(2 * h2 - 1)
        let nx = sin(phi) * cos(th), ny = cos(phi), nz = sin(phi) * sin(th)
        var ux = -ny, uy = nx; let uz = 0.0
        let ul = max(1e-6, sqrt(ux * ux + uy * uy)); ux /= ul; uy /= ul
        let vx = ny * uz - nz * uy, vy = nz * ux - nx * uz, vz = nx * uy - ny * ux
        let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)
        for k in 0..<ghostN {
            let a = (Double(k) / Double(ghostN)) * 2 * Double.pi
            let p = pt((ux * cos(a) + vx * sin(a)) * ro, (uy * cos(a) + vy * sin(a)) * ro, (uz * cos(a) + vz * sin(a)) * ro)
            let depth = (p.2 / ro + 1) / 2
            dots.append(Dot(x: p.0, y: p.1, z: p.2, r: (o["ghostR"] ?? 0.9) * rs, white: 0.72, a: (o["ghostA"] ?? 0.5) * (0.4 + 0.6 * depth)))
        }
        for m in 0..<particles {
            let a = t * speed + (Double(m) / Double(particles)) * 2 * Double.pi + h2 * 6
            let p = pt((ux * cos(a) + vx * sin(a)) * ro, (uy * cos(a) + vy * sin(a)) * ro, (uz * cos(a) + vz * sin(a)) * ro)
            let depth = (p.2 / ro + 1) / 2
            dots.append(Dot(x: p.0, y: p.1, z: p.2, r: ((o["partR"] ?? 1.2) + (o["partRDepth"] ?? 1.6) * depth) * rs, white: 0.3 - 0.22 * depth, a: 1))
        }
    }
    return finalize(dots, [], o["rMin"] ?? 0.3)
}

func frameGlobe(_ size: Double, _ t: Double, _ o: [String: Double]) -> Frame {
    let spin = 0.5, cx = size / 2, cy = size / 2, radius = (size / 2) * 0.82
    let tilt = 0.4 + 0.06 * sin(t * 0.35)
    let pt = makeProj(t * spin, tilt, cx, cy, radius)
    let scan = t * (spin + (1.7 - spin) * (o["scanMul"] ?? 1))
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    let dimBase = o["dimBase"] ?? 1
    var dots: [Dot] = []
    let latRings = Int(o["latRings"] ?? 17), lonDensity = Int(o["lonDensity"] ?? 44)
    for li in 0...latRings {
        let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * Double.pi
        let cosLat = cos(lat), sinLat = sin(lat)
        let lonCount = max(1, Int((abs(cosLat) * Double(lonDensity)).rounded()))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * Double.pi
            let p = pt(cosLat * cos(lon), sinLat, cosLat * sin(lon))
            let depth = (p.2 + 1) / 2
            let d = angleDelta(lon + t * spin, scan)
            let boost = exp(-(d * d) / 0.18) * max(0, p.2)
            dots.append(Dot(x: p.0, y: p.1, z: p.2, r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (o["rBoost"] ?? 1) * boost) * rs,
                            white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth,
                            a: dimBase + (1 - dimBase) * min(1, boost)))
        }
    }
    return finalize(dots, [], o["rMin"] ?? 0.3)
}

func makeMoves(_ count: Int) -> [(axis: Int, lo: Double, hi: Double, ang: Double)] {
    var moves: [(axis: Int, lo: Double, hi: Double, ang: Double)] = []
    for i in 0..<count {
        let axis = min(2, Int((hashD(Double(i), 2.3) * 3).rounded(.down)))
        let lo = -1.0 + 0.5 * Double(min(3, Int((hashD(Double(i), 5.9) * 4).rounded(.down))))
        let dir = hashD(Double(i), 7.7) < 0.5 ? 1.0 : -1.0
        moves.append((axis, lo, lo + 0.5, (dir * Double.pi) / 2))
    }
    return moves
}
func solveCycle(_ time: Double, _ count: Int, _ slotDur: Double, _ rest: Double) -> (amount: [Double], active: Int) {
    let cyc = 2 * Double(count) * slotDur + rest
    let tc = time.truncatingRemainder(dividingBy: cyc)
    var amount = [Double](repeating: 0, count: count)
    var active = -1
    if tc < 2 * Double(count) * slotDur {
        let slot = Int((tc / slotDur).rounded(.down))
        let p = (tc - Double(slot) * slotDur) / slotDur
        let cl = min(1, p / 0.7)
        let ep = 1 - pow(1 - cl, 3)
        if slot < count {
            for i in 0..<slot { amount[i] = 1 }
            amount[slot] = ep; active = slot
        } else {
            let u = 2 * count - 1 - slot
            for i in 0..<u { amount[i] = 1 }
            amount[u] = 1 - ep; active = u
        }
    }
    return (amount, active)
}
func applyMoves(_ pt: (Double, Double, Double), _ moves: [(axis: Int, lo: Double, hi: Double, ang: Double)], _ sc: (amount: [Double], active: Int)) -> (Double, Double, Double, Bool) {
    var x = pt.0, y = pt.1, z = pt.2
    var inActive = false
    for i in 0..<moves.count {
        if sc.amount[i] <= 0 { continue }
        let mv = moves[i]
        let coord = mv.axis == 0 ? x : mv.axis == 1 ? y : z
        if coord < mv.lo || coord >= mv.hi { continue }
        if i == sc.active { inActive = true }
        let a = mv.ang * sc.amount[i], ca = cos(a), sa = sin(a)
        if mv.axis == 0 { let y2 = y * ca - z * sa; z = y * sa + z * ca; y = y2 }
        else if mv.axis == 1 { let x2 = x * ca + z * sa; z = -x * sa + z * ca; x = x2 }
        else { let x2 = x * ca - y * sa; y = x * sa + y * ca; x = x2 }
    }
    return (x, y, z, inActive)
}
func frameRubik(_ size: Double, _ t: Double, _ o: [String: Double]) -> Frame {
    let cx = size / 2, cy = size / 2, R = (size / 2) * 0.82
    let pt = makeProj(t * 0.55, 0.35 + 0.1 * sin(t * 0.9), cx, cy, R)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    let moveCount = Int(o["moveCount"] ?? 14)
    let moves = makeMoves(moveCount)
    let sc = solveCycle(t, moveCount, 0.42, 1.2)
    var dots: [Dot] = []
    let latRings = Int(o["latRings"] ?? 15), lonDensity = Int(o["lonDensity"] ?? 40)
    for li in 0...latRings {
        let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * Double.pi
        let cosLat = cos(lat), sinLat = sin(lat)
        let lonCount = max(1, Int((abs(cosLat) * Double(lonDensity)).rounded()))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * Double.pi
            let r = applyMoves((cosLat * cos(lon), sinLat, cosLat * sin(lon)), moves, sc)
            let p = pt(r.0, r.1, r.2)
            let depth = (p.2 + 1) / 2
            dots.append(Dot(x: p.0, y: p.1, z: p.2,
                            r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (r.3 ? (o["rActive"] ?? 0.3) : 0)) * rs,
                            white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth - (r.3 ? 0.14 : 0),
                            a: 1))
        }
    }
    return finalize(dots, [], o["rMin"] ?? 0.3)
}
func frameWave(_ size: Double, _ t: Double, _ o: [String: Double]) -> Frame {
    let cx = size / 2, cy = size / 2, R = (size / 2) * 0.874
    let pt = makeProj(t * 0.18, 0.38, cx, cy, 1)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    var dots: [Dot] = []
    let rings = Int(o["rings"] ?? 15), lonDensity = Int(o["lonDensity"] ?? 40)
    for ri in 0...rings {
        let lat = -Double.pi / 2 + (Double(ri) / Double(rings)) * Double.pi
        let cosLat = cos(lat), sinLat = sin(lat)
        let w = 0.62 * sin(t * 2.1 - Double(ri) * 0.52) + 0.38 * sin(t * 1.27 + Double(ri) * 0.83)
        let rr = R * (0.88 + 0.105 * w)
        let lonCount = max(1, Int((abs(cosLat) * Double(lonDensity)).rounded()))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * Double.pi
            let p = pt(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
            let depth = (p.2 / R + 1) / 2
            let crest = max(0, w)
            dots.append(Dot(x: p.0, y: p.1, z: p.2,
                            r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth) * (1 + 0.4 * crest) * rs,
                            white: 0.66 - 0.56 * depth - 0.1 * crest, a: 1))
        }
    }
    return finalize(dots, [], o["rMin"] ?? 0.3)
}
func frameWeb(_ size: Double, _ t: Double, _ o: [String: Double]) -> Frame {
    let cx = size / 2, cy = size / 2, R = (size / 2) * 0.8 * (o["spread"] ?? 1)
    let pt = makeProj(t * 0.12, 0.32, cx, cy, R)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    let nodeN = Int(o["nodeN"] ?? 30), thr = o["thr"] ?? 0.72
    let nodeR = o["nodeR"] ?? 1.4, nodeRDepth = o["nodeRDepth"] ?? 1.8
    var nodes: [(Double, Double, Double)] = []
    for i in 0..<nodeN {
        let d = fibDir(i, nodeN)
        let x = d.0 + 0.3 * (vnoise(Double(i) * 0.31 + 9, t * 0.24) - 0.5) * 2
        let y = d.1 + 0.3 * (vnoise(Double(i) * 0.53 + 27, t * 0.21) - 0.5) * 2
        let z = d.2 + 0.3 * (vnoise(Double(i) * 0.77 + 55, t * 0.27) - 0.5) * 2
        let l = sqrt(x * x + y * y + z * z)
        nodes.append((x / l, y / l, z / l))
    }
    var lines: [Line] = [], dots: [Dot] = []
    for i in 0..<nodeN {
        for j in (i + 1)..<nodeN {
            let dx = nodes[i].0 - nodes[j].0, dy = nodes[i].1 - nodes[j].1, dz = nodes[i].2 - nodes[j].2
            let dist = sqrt(dx * dx + dy * dy + dz * dz)
            if dist >= thr { continue }
            let p1 = pt(nodes[i].0, nodes[i].1, nodes[i].2)
            let p2 = pt(nodes[j].0, nodes[j].1, nodes[j].2)
            let depth = ((p1.2 + p2.2) / 2 + 1) / 2
            lines.append(Line(x1: p1.0, y1: p1.1, x2: p2.0, y2: p2.1, white: 0.42, a: (1 - dist / thr) * (0.3 + 0.55 * depth), w: max(0.6, (o["lineW"] ?? 0.8) * rs)))
        }
    }
    for i in 0..<nodeN {
        let p = pt(nodes[i].0, nodes[i].1, nodes[i].2)
        let depth = (p.2 + 1) / 2
        let pulse = 1 + 0.25 * sin(t * 1.4 + Double(i) * 2.7)
        dots.append(Dot(x: p.0, y: p.1, z: p.2, r: (nodeR + nodeRDepth * depth) * pulse * rs, white: 0.55 - 0.45 * depth, a: 1))
    }
    let signals = Int(o["signals"] ?? 5)
    for s in 0..<signals {
        let seg = Int((t * 0.55 + Double(s) * 7.31).rounded(.down))
        let a = Int((hashD(Double(seg), Double(s) * 3.1 + 1.7) * Double(nodeN)).rounded(.down))
        let b = Int((hashD(Double(seg), Double(s) * 5.7 + 4.2) * Double(nodeN)).rounded(.down))
        if a == b || a >= nodeN || b >= nodeN { continue }
        let f = frac(t * 0.55 + Double(s) * 7.31)
        var x = lerp(nodes[a].0, nodes[b].0, f), y = lerp(nodes[a].1, nodes[b].1, f), z = lerp(nodes[a].2, nodes[b].2, f)
        let l = max(1e-6, sqrt(x * x + y * y + z * z)); x /= l; y /= l; z /= l
        let p = pt(x, y, z)
        let depth = (p.2 + 1) / 2
        dots.append(Dot(x: p.0, y: p.1, z: p.2, r: (nodeR * 1.5 + nodeRDepth * depth) * rs, white: 0.05, a: 0.5 + 0.5 * depth))
    }
    return finalize(dots, lines, o["rMin"] ?? 0.3)
}
func frameBraid(_ size: Double, _ t: Double, _ o: [String: Double]) -> Frame {
    let cx = size / 2, cy = size / 2, R = (size / 2) * 0.76
    let pt = makeProj(t * 0.4, 0.3, cx, cy, 1)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    var dots: [Dot] = []
    let ghostN = Int(o["ghostN"] ?? 150)
    for i in 0..<ghostN {
        let d = fibDir(i, ghostN)
        let p = pt(d.0 * R, d.1 * R, d.2 * R)
        let depth = (p.2 / R + 1) / 2
        dots.append(Dot(x: p.0, y: p.1, z: p.2, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
    }
    let strandN = Int(o["strandN"] ?? 52), turns = o["turns"] ?? 3
    for s in 0..<3 {
        let phase = (Double(s) / 3) * 2 * Double.pi
        for i in 0..<strandN {
            let u = (frac(Double(i) / Double(strandN) + t * 0.045) * 2 - 1) * 0.96
            let surf = sqrt(max(0, 1 - u * u))
            let endFade = min(1, (1 - abs(u)) / 0.1)
            let a = u * Double.pi * turns + phase
            let weave = 1 + 0.075 * sin(u * Double.pi * turns * 2 + phase * 2 + t * 0.8)
            let rr = surf * R * weave
            let p = pt(cos(a) * rr, u * R * weave, sin(a) * rr)
            let depth = (p.2 / R + 1) / 2
            dots.append(Dot(x: p.0, y: p.1, z: p.2, r: ((o["rBase"] ?? 1.2) + (o["rDepth"] ?? 1.8) * depth) * rs,
                            white: 0.55 - 0.45 * depth, a: endFade * (0.45 + 0.55 * depth)))
        }
    }
    return finalize(dots, [], o["rMin"] ?? 0.3)
}
func frameRibbon(_ size: Double, _ t: Double, _ o: [String: Double]) -> Frame {
    let cx = size / 2, cy = size / 2, R = (size / 2) * 0.78
    let spin = o["spin"] ?? 1, camTilt = 0.3
    let pt = makeProj(t * 0.1 * spin, camTilt, cx, cy, 1)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    var dots: [Dot] = []
    let ghostN = Int(o["ghostN"] ?? 150)
    for i in 0..<ghostN {
        let d = fibDir(i, ghostN)
        let p = pt(d.0 * R, d.1 * R, d.2 * R)
        let depth = (p.2 / R + 1) / 2
        dots.append(Dot(x: p.0, y: p.1, z: p.2, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
    }
    let ya = t * 0.24 * spin
    let ta = (o["faceOn"] ?? 0) != 0 ? -camTilt : 0.55 + 0.3 * sin(t * 0.18) * spin
    let ux = cos(ya), uy = 0.0, uz = sin(ya)
    let vx = -uz * sin(ta), vy = cos(ta), vz = ux * sin(ta)
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
    let wobAmp = 0.23 * (o["wobMul"] ?? 1)
    let baseR = (o["faceOn"] ?? 0) != 0 ? R / (1 + 0.85 * wobAmp) : R
    let segs = Int(o["segs"] ?? 88)
    let lanes = max(1, Int(((o["lanes"] ?? 5) * (o["bandMul"] ?? 1)).rounded()))
    for w in 0..<lanes {
        let laneOff = (Double(w) - Double(lanes - 1) / 2) * 0.075
        let edge = abs(Double(w) - Double(lanes - 1) / 2) / max(1, Double(lanes - 1) / 2)
        for k in 0..<segs {
            let a = (Double(k) / Double(segs)) * 2 * Double.pi
            let wob = (0.16 * sin(a * 3 - t * 1.7 + Double(w) * 0.22) + 0.07 * sin(a * 5 + t * 1.1)) * (o["wobMul"] ?? 1)
            let radial = (o["faceOn"] ?? 0) != 0 ? 1 + wob : 1.0
            let off = (o["faceOn"] ?? 0) != 0 ? laneOff : laneOff + wob
            let x = ux * cos(a) + vx * sin(a) + nx * off
            let y = uy * cos(a) + vy * sin(a) + ny * off
            let z = uz * cos(a) + vz * sin(a) + nz * off
            let l = sqrt(x * x + y * y + z * z)
            let rr = baseR * radial
            let p = pt((x / l) * rr, (y / l) * rr, (z / l) * rr)
            let depth = (p.2 / R + 1) / 2
            dots.append(Dot(x: p.0, y: p.1, z: p.2,
                            r: ((o["rBase"] ?? 1.1) + (o["rDepth"] ?? 1.7) * depth) * (1 - 0.25 * edge) * rs,
                            white: 0.52 - 0.44 * depth + 0.18 * edge, a: 0.4 + 0.6 * depth))
        }
    }
    return finalize(dots, [], o["rMin"] ?? 0.3)
}
func smoothE(_ x: Double) -> Double { x * x * (3 - 2 * x) }
func polyPath(_ verts: [(Double, Double)]) -> (Double) -> (Double, Double) {
    let V = verts.count
    var L: [Double] = []
    var total = 0.0
    for i in 0..<V {
        let a = verts[i], b = verts[(i + 1) % V]
        let l = hypot(b.0 - a.0, b.1 - a.1)
        L.append(l); total += l
    }
    return { f in
        var target = f * total, i = 0
        while target > L[i] && i < V - 1 { target -= L[i]; i += 1 }
        let a = verts[i], b = verts[(i + 1) % V]
        let ff = L[i] != 0 ? min(1, target / L[i]) : 0
        return (a.0 + (b.0 - a.0) * ff, a.1 + (b.1 - a.1) * ff)
    }
}
func frameMorph(_ size: Double, _ t: Double, _ o: [String: Double]) -> Frame {
    let circle: (Double) -> (Double, Double) = { f in
        let a = -Double.pi / 2 + f * 2 * Double.pi
        return (cos(a) * 0.24, sin(a) * 0.24)
    }
    let triangle = polyPath([(0.0, -0.26), (0.24, 0.16), (-0.24, 0.16)])
    let square = polyPath([(0, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2), (-0.2, -0.2)])
    let cycle: [(Double) -> (Double, Double)] = [circle, triangle, square]
    let K = cycle.count, HOLD = 1.4, MORPH = 0.9, SEG = HOLD + MORPH
    let tc = t.truncatingRemainder(dividingBy: SEG * Double(K))
    let k = Int((tc / SEG).rounded(.down))
    let local = tc - Double(k) * SEG
    let m = local > HOLD ? smoothE((local - HOLD) / MORPH) : 0
    let sprd = o["spread"] ?? 1
    let pA = cycle[k], pB = cycle[(k + 1) % K]
    let M = 160
    var pts: [(Double, Double)] = []
    for i in 0..<M {
        let f = Double(i) / Double(M)
        let a = pA(f), b = pB(f)
        pts.append(((a.0 + (b.0 - a.0) * m) * sprd, (a.1 + (b.1 - a.1) * m) * sprd))
    }
    var L: [Double] = []; var total = 0.0
    for i in 0..<M {
        let a = pts[i], b = pts[(i + 1) % M]
        let l = hypot(b.0 - a.0, b.1 - a.1)
        L.append(l); total += l
    }
    let n = max(6, Int((34 * (o["iconD"] ?? 1)).rounded()))
    let re = (o["rDot"] ?? 0.021) * 1.35 * sprd
    let pulse = 1 + 0.02 * sin(local * 3.1)
    var dots: [Dot] = []
    let c2 = size / 2
    var seg = 0; var acc = 0.0
    for k2 in 0..<n {
        let target = (Double(k2) / Double(n)) * total
        while acc + L[seg] < target && seg < M - 1 { acc += L[seg]; seg += 1 }
        let a = pts[seg], b = pts[(seg + 1) % M]
        let f = L[seg] != 0 ? min(1, (target - acc) / L[seg]) : 0
        let x = (a.0 + (b.0 - a.0) * f) * pulse
        let y = (a.1 + (b.1 - a.1) * f) * pulse
        dots.append(Dot(x: c2 + x * size, y: c2 + y * size, z: 0, r: max(0.35, re * size), white: 0.1, a: 1))
    }
    return finalize(dots, [], o["rMin"] ?? 0.25)
}

let FRAMES: [String: (Double, Double, [String: Double]) -> Frame] = [
    "orbits": frameOrbits, "globe": frameGlobe, "rubik": frameRubik, "wave": frameWave,
    "web": frameWeb, "braid": frameBraid, "ribbon": frameRibbon, "ring": frameRibbon, "morph": frameMorph
]

// MARK: - OrbView (Canvas, 60 fps)

final class OrbView: NSView {
    var state: String = "breathing" { didSet { if state != oldValue { needsDisplay = true } } }
    private var timer: Timer?
    private var t: Double = 0
    private var resolved: (mode: String, speed: Double, opts: [String: Double]) = resolvePreset("breathing")
    /// Manuell gepinnt (Menü): der Poller überschreibt den gewählten State
    /// nicht mehr — „Live folgen" löst das Pin.
    private var pinned = false

    // State-Transition (Morph): alter State wird als Snapshot eingefroren und
    // die Punkte interpolieren weich zu den Positionen des neuen State.
    private var fromDots: [Dot] = []
    private var fromLines: [Line] = []
    private var transitionT: Double = 1.0   // 1 = keine Transition aktiv
    private let transitionDuration: Double = 0.8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { timer?.invalidate() }

    private func tick() {
        t += 1.0 / 60.0 * resolved.speed
        if transitionT < 1 {
            transitionT = min(1, transitionT + 1.0 / 60.0 / transitionDuration)
        }
        needsDisplay = true
    }

    private func angleOf(_ d: Dot) -> Double {
        let cx = Double(bounds.width) / 2, cy = Double(bounds.height) / 2
        return atan2(d.y - cy, d.x - cx)
    }
    private func smoothStep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// State wechseln MIT Morph-Übergang (Snapshots + Interpolation).
    private func beginTransition(to newState: String) {
        let size = Double(bounds.width)
        let oldFrame = FRAMES[resolved.mode]!(size, t, resolved.opts)
        fromDots = oldFrame.dots.sorted { angleOf($0) < angleOf($1) }
        fromLines = oldFrame.lines
        resolved = resolvePreset(newState)
        state = newState
        transitionT = 0
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }   // NSView-y nach unten → nicht gespiegelt
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = Double(bounds.width)
        guard size > 0 else { return }
        ctx.clear(bounds)
        let appearance = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let frame = FRAMES[resolved.mode]!(size, t, resolved.opts)

        if transitionT < 1 {
            let ease = smoothStep(transitionT)
            // Alte Linien blenden aus, neue ein
            for l in fromLines {
                paintOneLine(ctx, l, appearance, alphaMul: 1 - ease)
            }
            for l in frame.lines {
                paintOneLine(ctx, l, appearance, alphaMul: ease)
            }
            // Punkte: indexweise per Winkel-Sortierung paaren; neue Punkte
            // ohne Partner wachsen aus dem Zentrum (alpha 0 → 1)
            let toDots = frame.dots.sorted { angleOf($0) < angleOf($1) }
            let cx = size / 2, cy = size / 2
            var morphed: [Dot] = []
            morphed.reserveCapacity(toDots.count)
            for (i, d) in toDots.enumerated() {
                let from: Dot
                if i < fromDots.count {
                    from = fromDots[i]
                } else {
                    from = Dot(x: cx, y: cy, z: d.z, r: d.r, white: d.white, a: 0)
                }
                morphed.append(Dot(x: lerp(from.x, d.x, ease),
                                   y: lerp(from.y, d.y, ease),
                                   z: lerp(from.z, d.z, ease),
                                   r: lerp(from.r, d.r, ease),
                                   white: lerp(from.white, d.white, ease),
                                   a: lerp(from.a, d.a, ease)))
            }
            paint(ctx, morphed, appearance)
        } else {
            if !frame.lines.isEmpty { paintLines(ctx, frame.lines, appearance) }
            paint(ctx, frame.dots, appearance)
        }
    }
    private func paintOneLine(_ ctx: CGContext, _ l: Line, _ dark: Bool, alphaMul: Double) {
        let w = min(1, max(0, l.white))
        let g = dark ? 1 - w : w
        let gray = Int((g * 255).rounded())
        ctx.setStrokeColor(CGColor(red: CGFloat(gray) / 255, green: CGFloat(gray) / 255, blue: CGFloat(gray) / 255, alpha: CGFloat(l.a * alphaMul)))
        ctx.setLineWidth(CGFloat(l.w))
        ctx.move(to: CGPoint(x: l.x1, y: l.y1))
        ctx.addLine(to: CGPoint(x: l.x2, y: l.y2))
        ctx.strokePath()
    }
    private func paint(_ ctx: CGContext, _ dots: [Dot], _ dark: Bool) {
        for d in dots {
            let alpha = d.a
            let w = min(1, max(0, d.white))
            let g = dark ? 1 - w : w
            let gray = Int((g * 255).rounded())
            ctx.setFillColor(CGColor(red: CGFloat(gray) / 255, green: CGFloat(gray) / 255, blue: CGFloat(gray) / 255, alpha: CGFloat(alpha)))
            ctx.fillEllipse(in: CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2))
        }
    }
    private func paintLines(_ ctx: CGContext, _ lines: [Line], _ dark: Bool) {
        for l in lines {
            let w = min(1, max(0, l.white))
            let g = dark ? 1 - w : w
            let gray = Int((g * 255).rounded())
            ctx.setStrokeColor(CGColor(red: CGFloat(gray) / 255, green: CGFloat(gray) / 255, blue: CGFloat(gray) / 255, alpha: CGFloat(l.a)))
            ctx.setLineWidth(CGFloat(l.w))
            ctx.move(to: CGPoint(x: l.x1, y: l.y1))
            ctx.addLine(to: CGPoint(x: l.x2, y: l.y2))
            ctx.strokePath()
        }
    }
    /// Wird vom Poller aufgerufen, wenn das Backend einen neuen State meldet.
    func applyRemoteState(_ newState: String) {
        if pinned { return }
        let mode = STATE_TO_MODE[newState]
        if mode != nil && newState != state {
            beginTransition(to: newState)
        }
    }
    /// Manuelles Setzen (Menü) — pinnt bis „Live folgen".
    func setState(_ newState: String) {
        pinned = true
        if newState != state {
            beginTransition(to: newState)
        }
    }
    func unpin() { pinned = false }
}

// MARK: - Status-Poller (Hermes-Plugin-Backend, 127.0.0.1:8799)

final class StatusPoller {
    private let orb: OrbView
    private var timer: Timer?
    private let url = URL(string: "http://127.0.0.1:8799/status")!
    private var inFlight = false
    private var generation = 0
    init(orb: OrbView) { self.orb = orb }
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }
    deinit { timer?.invalidate() }
    private func poll() {
        guard !inFlight else { return }   // kein Overlap → keine Out-of-Order-Lügen
        inFlight = true
        let gen = generation
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard gen == self.generation,
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      error == nil, let data,
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let state = obj["state"] as? String else { return }
                self.orb.applyRemoteState(state)
            }
        }.resume()
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var orbView: OrbView!
    private var poller: StatusPoller?
    private var statusItem: NSStatusItem?
    private var clickThrough = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let size: CGFloat = 96
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: NSScreen.main!.frame.maxX - size - 24, y: NSScreen.main!.frame.maxY - size - 60))

        orbView = OrbView(frame: rect)
        orbView.state = "breathing"
        window.contentView = orbView

        // Rechtsklick-Menü
        let menu = NSMenu()
        let statesMenu = NSMenu()
        let order = ["working", "searching", "solving", "listening", "connecting", "weaving", "composing", "breathing", "shaping"]
        for s in order {
            let item = NSMenuItem(title: s.capitalized, action: #selector(pickState(_:)), keyEquivalent: "")
            item.representedObject = s
            item.target = self
            statesMenu.addItem(item)
        }
        let statesItem = NSMenuItem(title: "State", action: nil, keyEquivalent: "")
        statesItem.submenu = statesMenu
        menu.addItem(statesItem)
        menu.addItem(NSMenuItem.separator())
        for (title, sel) in [("Klein (40)", #selector(setSizeSmall)), ("Mittel (96)", #selector(setSizeMid)), ("Groß (160)", #selector(setSizeLarge))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let ct = NSMenuItem(title: "Durchklickbar", action: #selector(toggleClickThrough), keyEquivalent: "")
        ct.target = self
        menu.addItem(ct)
        let quit = NSMenuItem(title: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        orbView.menu = menu

        window.orderFrontRegardless()

        setupStatusItem()
        poller = StatusPoller(orb: orbView)
        poller?.start()
        NSLog("[thinking-orb] running — state breathing")
    }

    /// Escape-Hatch: Accessory-App (LSUIElement, kein Dock-Icon) braucht ein
    /// Menübar-Icon — sonst wäre „Durchklickbar" ein Lockout ohne Ausweg.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            btn.image = NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: "Thinking Orb")
        }
        let menu = NSMenu()
        let live = NSMenuItem(title: "Live folgen", action: #selector(unpinState), keyEquivalent: "")
        live.target = self
        menu.addItem(live)
        let ct = NSMenuItem(title: "Durchklickbar", action: #selector(toggleClickThrough), keyEquivalent: "")
        ct.target = self
        menu.addItem(ct)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func pickState(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? String { orbView.setState(s) }
    }
    @objc private func unpinState() { orbView.unpin() }
    @objc private func setSizeSmall() { resize(40) }
    @objc private func setSizeMid() { resize(96) }
    @objc private func setSizeLarge() { resize(160) }
    private func resize(_ s: CGFloat) {
        var f = window.frame
        f.size = NSSize(width: s, height: s)
        window.setFrame(f, display: true)
        orbView.frame = NSRect(x: 0, y: 0, width: s, height: s)
    }
    @objc private func toggleClickThrough() {
        clickThrough.toggle()
        window.ignoresMouseEvents = clickThrough
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
