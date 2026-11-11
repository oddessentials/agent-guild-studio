class_name YardModel
## A port of agent-guild's web/yard/model.mjs (docs/yard/CONTRACT.md), the
## staging contract every Yard client follows. tests/contract_test.gd reproduces
## every golden vector of the agent-guild commit CI pins (AGENT_GUILD_COMMIT).
## Numbers stay doubles throughout (Godot's Vector types are single
## precision), and JavaScript's own rounding, hypot, hash wraparound, string
## order and stable sort are copied where results depend on them.

const PROVIDER_ORDER := ["anthropic", "openai", "google", "xai", "shell", "docker"]
const GILDED := ["terminal-ai-chat"]

const EFFECTS := {
	"smoke": { "rate": [5, 12], "life": 4.5, "rise": .55, "drift": [.28, -.12], "spread": .12, "size": [.35, 1.3], "color": 0x9a948c, "opacity": .5, "glow": false },
	"vent": { "rate": [8, 18], "life": 1.8, "rise": .9, "drift": [.08, .05], "spread": .18, "size": [.25, .9], "color": 0xeef4ff, "opacity": .45, "glow": false },
	"rooftop": { "rate": [6, 14], "life": 2.6, "rise": .7, "drift": [.2, -.08], "spread": .3, "size": [.3, 1.1], "color": 0xf2f2ee, "opacity": .38, "glow": false },
	"fireflies": { "rate": [4, 10], "life": 6, "rise": .05, "drift": [0, 0], "spread": 1.4, "size": [.22, .22], "color": 0xe4ff6e, "opacity": 1, "glow": true, "wander": true },
}

const WORLDS := {
	"guild": { "title": "The Guild Yard", "subtitle": "A place for every great endeavour", "asset": "guild",
		"characters": "hero_", "helpers": { "agent": "familiar_", "shell": "drone_" },
		"hemi": 0xc4dced, "sun": { "light": 0xffe0ad, "dark": 0xff9a5c },
		"station": { "asset": "guild_station", "surface": 1 }, "effect": "smoke" },
	"orbital": { "title": "Orbital Station", "subtitle": "Your crew, at the edge of possibility", "asset": "orbital",
		"characters": "robot_", "helpers": { "agent": "drone_", "shell": "drone_" },
		"hemi": 0xa7c9ff, "sun": { "light": 0xfff8f0, "dark": 0xffa46e },
		"station": { "asset": "orbital_station", "surface": 1 }, "effect": "vent" },
	"grove": { "title": "The Living Grove", "subtitle": "Good work takes root here", "asset": "grove",
		"characters": "spirit_", "helpers": { "agent": "familiar_", "shell": "drone_" },
		"hemi": 0xccebd6, "sun": { "light": 0xffe0ad, "dark": 0xffe0ad },
		"station": { "asset": "grove_station", "surface": .67 }, "effect": "fireflies" },
	"professional": { "title": "Operations Campus", "subtitle": "A clear view of work in progress", "asset": "professional",
		"characters": "staff_", "helpers": { "agent": "bot_", "shell": "bot_" },
		"hemi": 0xc8d6e2, "sun": { "light": 0xfff0d8, "dark": 0xff9a5c },
		"station": { "asset": "professional_station", "surface": 1 }, "effect": "rooftop" },
	"goblinville": { "title": "Goblinville Works", "subtitle": "Steam up, and mind the boardwalks", "asset": "goblinville",
		"characters": "goblin_", "helpers": { "agent": "goblin_familiar_", "shell": "goblin_helper_" },
		"hemi": 0xc9d6c8, "sun": { "light": 0xffe2b8, "dark": 0xff8c50 },
		"station": { "asset": "goblinville_station", "surface": 1 }, "effect": "smoke" },
	"gnomeland": { "title": "Gnomeland Village", "subtitle": "Measure twice, enchant once", "asset": "gnomeland",
		"characters": "gnome_", "helpers": { "agent": "gnome_familiar_", "shell": "gnome_helper_" },
		"hemi": 0xcbd9d6, "sun": { "light": 0xffe4bf, "dark": 0xff8d52 },
		"station": { "asset": "gnomeland_station", "surface": .75 }, "effect": "smoke" },
}

const CAMERA := {
	"offset": [19, 24, 31], "target": [0, 1, 0], "height": 30, "near": .1, "far": 400,
	"zoom": { "overview": 1.02, "focus": 1.7, "min": .6, "max": 3.8 },
	"maxAspect": 4,
	"pan": { "minX": -20, "maxX": 20, "minZ": -16, "maxZ": 30 },
}
const SUN := { "light": [-12, 25, 15], "dark": [-12, 3.4, 15] }

const STAGING := {
	"restAfter": 20000,
	"arrival": 15000,
	"stationFace": -.3,
	"door": 2.9,
	"plaza": { "x": 0, "z": 0, "half": 2.2, "rings": [[3.2, 10], [4.4, 14], [5.6, 18]] },
	"hall": { "half": 2.65, "docker": 3.4, "margin": .55 },
	"station": { "spacing": 2, "gap": .75, "turn": .7, "half": .55 },
	"look": { "range": 2.5, "yaw": .7, "pitch": .3, "neck": .4 },
}

const CLIPS := {
	"character": { "walk": "walk", "work": ["work_0", "work_1"], "pause": ["pause"], "rest": ["idle_0", "idle_1", "idle_2"], "done": ["done"] },
	"helper": ["idle", "working", "waiting", "done", "move"],
}

const ARRANGEMENTS := ["counter", "left", "right"]

static func characterIndex(id: String) -> int:
	return PROVIDER_ORDER.find(id) if PROVIDER_ORDER.has(id) else PROVIDER_ORDER.find("shell")

static func skeleton(kind: String) -> Array:
	var trunk := ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]
	if kind == "helper":
		return trunk
	var out := trunk.duplicate()
	for side in ["Left", "Right"]:
		for limb in ["Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toes"]:
			out.append(side + limb)
		out.append("Prop" + side)
	return out

# --- JavaScript arithmetic ---------------------------------------------------

## Math.round: halves go up, so -2.5 rounds to -2.
static func js_round(v: float) -> float:
	return floor(v + 0.5)

static func round3(v: float) -> float:
	return js_round(v * 1000.0) / 1000.0

## V8's Math.hypot: scaled by the largest value, Kahan-summed.
static func hypot(a: float, b: float, c = null) -> float:
	var values := [absf(a), absf(b)]
	if c != null:
		values.append(absf(c))
	var top := 0.0
	for v in values:
		if v > top:
			top = v
	if top == INF:
		return INF
	if top == 0.0:
		return 0.0
	var sum := 0.0
	var compensation := 0.0
	for v in values:
		var n: float = v / top
		var summand: float = n * n - compensation
		var preliminary: float = sum + summand
		compensation = (preliminary - sum) - summand
		sum = preliminary
	return sqrt(sum) * top

static func clamp_num(value: float, lo: float, hi: float) -> float:
	return minf(hi, maxf(lo, value))

## A 32-bit signed integer, as JavaScript's `| 0` leaves it.
static func _int32(n: int) -> int:
	n = n & 0xFFFFFFFF
	return n - 0x100000000 if n >= 0x80000000 else n

## The UTF-16 code units JavaScript sees in a string.
static func _utf16(text: String) -> Array:
	var out := []
	for i in text.length():
		var c := text.unicode_at(i)
		if c > 0xFFFF:
			c -= 0x10000
			out.append(0xD800 + (c >> 10))
			out.append(0xDC00 + (c & 0x3FF))
		else:
			out.append(c)
	return out

## `for (const char of value)` visits code points; charCodeAt(0) of each is
## its first UTF-16 unit.
static func js_hash(value) -> int:
	var n := 0
	var text := _js_string(value)
	for i in text.length():
		var c := text.unicode_at(i)
		if c > 0xFFFF:
			c = 0xD800 + ((c - 0x10000) >> 10)
		n = _int32(((n << 5) - n) + c)
	return absi(n)

## String(value) for the values the contract hashes.
static func _js_string(value) -> String:
	if value is float and value == floor(value) and absf(value) < 1e15:
		return str(int(value))
	return str(value)

# ICU's root collation order for ASCII, which String.prototype.localeCompare
# uses: whitespace, punctuation and symbols, digits, then letters with case
# only breaking ties (lower first).
const _COLLATION := "\t\n\u000b\u000c\r _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789abcdefghijklmnopqrstuvwxyz"

static func _primary(c: int) -> int:
	var lower := c + 32 if c >= 65 and c <= 90 else c
	var at := _COLLATION.find(char(lower)) if lower < 128 else -1
	return at if at >= 0 else 1000 + c

## a.localeCompare(b) for ASCII text such as ids and ISO times.
static func locale_compare(a: String, b: String) -> int:
	var n := mini(a.length(), b.length())
	for i in n:
		var pa := _primary(a.unicode_at(i))
		var pb := _primary(b.unicode_at(i))
		if pa != pb:
			return -1 if pa < pb else 1
	if a.length() != b.length():
		return -1 if a.length() < b.length() else 1
	for i in n:
		var ua := a.unicode_at(i) >= 65 and a.unicode_at(i) <= 90
		var ub := b.unicode_at(i) >= 65 and b.unicode_at(i) <= 90
		if ua != ub:
			return 1 if ua else -1
	return 0

## A stable merge sort, as Array.prototype.sort is.
static func stable_sort(items: Array, compare: Callable) -> Array:
	if items.size() < 2:
		return items.duplicate()
	var mid := items.size() / 2
	var left := stable_sort(items.slice(0, mid), compare)
	var right := stable_sort(items.slice(mid), compare)
	var out := []
	var i := 0
	var j := 0
	while i < left.size() and j < right.size():
		if compare.call(right[j], left[i]) < 0:
			out.append(right[j]); j += 1
		else:
			out.append(left[i]); i += 1
	out.append_array(left.slice(i))
	out.append_array(right.slice(j))
	return out

static func _by_created(a: Dictionary, b: Dictionary) -> int:
	var c := locale_compare(String(a.createdAt), String(b.createdAt))
	return c if c != 0 else locale_compare(String(a.id), String(b.id))

## Date.parse for ISO 8601 times, in epoch milliseconds, or null.
static func parse_time(value) -> Variant:
	if value == null:
		return null
	var re := RegEx.create_from_string("^(\\d{4})-(\\d{2})-(\\d{2})(?:T(\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.(\\d{1,9}))?)?(Z|[+-]\\d{2}:\\d{2})?)?$")
	var m := re.search(String(value))
	if m == null:
		return null
	var dt := { "year": m.get_string(1).to_int(), "month": m.get_string(2).to_int(), "day": m.get_string(3).to_int(),
		"hour": m.get_string(4).to_int(), "minute": m.get_string(5).to_int(), "second": m.get_string(6).to_int() }
	var ms := float(Time.get_unix_time_from_datetime_dict(dt)) * 1000.0
	var frac := m.get_string(7)
	if frac != "":
		ms += floorf(("0." + frac).to_float() * 1000.0 + 1e-6)
	var zone := m.get_string(8)
	if zone != "" and zone != "Z":
		var sign := -1.0 if zone[0] == "+" else 1.0
		ms += sign * (zone.substr(1, 2).to_int() * 60 + zone.substr(4, 2).to_int()) * 60000.0
	return ms

static func iso_time(ms: float) -> String:
	var whole := int(floorf(ms / 1000.0))
	var rest := int(ms - whole * 1000.0)
	return Time.get_datetime_string_from_unix_time(whole) + ".%03dZ" % rest

# --- View --------------------------------------------------------------------

static func min_zoom(aspect: float) -> float:
	return maxf(CAMERA.zoom.min, CAMERA.zoom.min * aspect / CAMERA.maxAspect)

static func clamp_pan(p: Dictionary) -> Dictionary:
	var pan: Dictionary = CAMERA.pan
	return { "x": clamp_num(p.x, pan.minX, pan.maxX), "z": clamp_num(p.z, pan.minZ, pan.maxZ) }

static func _normalize(v: Array) -> Array:
	var n := sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	return [v[0] / n, v[1] / n, v[2] / n]

static func _cross(a: Array, b: Array) -> Array:
	return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

## Screen right and up as world directions, matching a camera looking at the target.
static func view_basis() -> Dictionary:
	var o: Array = CAMERA.offset
	var forward := _normalize([-o[0], -o[1], -o[2]])
	var right := _normalize(_cross(forward, [0, 1, 0]))
	return { "forward": forward, "right": right, "up": _cross(right, forward) }

# --- Sessions ----------------------------------------------------------------

static func session_pose(s: Dictionary) -> String:
	if s.get("status") == "exited":
		return "exited"
	return "working" if s.get("activity") == "active" else "resting"

static func familiar_pose(agent: Dictionary) -> String:
	var status = agent.get("status")
	return status if status in ["working", "waiting", "idle", "done"] else "idle"

const SHOWN_HELPERS := 6

static func marks_for(s: Dictionary, mode: String) -> Dictionary:
	if s.get("status") == "exited":
		var code = s.get("exitCode")
		if s.get("multiplexer") != null:
			return { "crew": null, "helpers": [] }
		var failed: bool = s.get("signal") not in [null, ""] or (0.0 if code == null else float(code)) != 0.0
		return { "crew": "failed" if failed else "exited", "helpers": [] }
	var agents: Array = s.get("agents", [])
	var waiting := 0
	var shown := []
	for i in agents.size():
		if familiar_pose(agents[i]) == "waiting":
			waiting += 1
			if i < SHOWN_HELPERS:
				shown.append(agents[i].id)
	var crew = "waiting" if waiting > shown.size() else ("asleep" if mode == "rest" and agents.is_empty() and (s.get("shells", []) as Array).is_empty() else null)
	return { "crew": crew, "helpers": shown }

static func provider_positions(providers: Array) -> Dictionary:
	var slots := [[-7, -5], [0, -7], [7, -5], [-8, 3], [8, 3], [-10, 11]]
	var result := {}
	var extra := providers.filter(func(p): return not PROVIDER_ORDER.has(p.id))
	for p in providers:
		var i := PROVIDER_ORDER.find(p.id)
		var n := extra.find(p) + 1
		var x: float
		var z: float
		if i < 0:
			x = float(((n % 5) - 2) * 5)
			z = 11.0 + floorf(n / 5.0) * 6.0
		else:
			x = slots[i][0]
			z = slots[i][1]
		result[p.id] = { "x": x, "z": z }
	return result

static func layout_sessions(sessions: Array, providers: Array, previous := {}) -> Dictionary:
	var anchors := provider_positions(providers)
	var used := {}
	var result := {}
	var group := func(s): return s.provider.id if anchors.has(s.provider.id) else "__tasks"
	var sorted := stable_sort(sessions, _by_created)
	for s in sorted:
		var key: String = group.call(s)
		if not used.has(key):
			used[key] = {}
		var old = previous.get(s.id)
		if old != null and old.group == key and not used[key].has(old.slot):
			used[key][old.slot] = true
			result[s.id] = { "group": key, "slot": old.slot }
	for s in sorted:
		var key: String = group.call(s)
		if not result.has(s.id):
			var slot := 0
			while used[key].has(slot):
				slot += 1
			used[key][slot] = true
			result[s.id] = { "group": key, "slot": slot }
		var entry: Dictionary = result[s.id]
		var origin: Dictionary = anchors.get(key, { "x": 0.0, "z": 4.0 })
		var dir := -1.0 if key == "anthropic" or key == "google" or key == "xai" else 1.0
		var size := 1.3 if key == "docker" else 1.0
		var slot: int = entry.slot
		entry.x = origin.x + dir * (float(slot % 4) - 1.5) * STAGING.station.spacing * size
		entry.z = origin.z + (3.25 + floorf(slot / 4.0) * 1.6) * size
	return result

static func _quiet_since(s: Dictionary) -> Variant:
	var t = parse_time(s.get("lastOutputAt"))
	if t == null:
		t = parse_time(s.get("startedAt"))
	if t == null:
		t = parse_time(s.get("createdAt"))
	return t

static func staging_mode(s: Dictionary, now: float) -> String:
	if s.get("status") == "exited":
		return "done"
	if s.get("activity") == "active":
		return "work"
	var quiet = _quiet_since(s)
	return "rest" if quiet != null and now - quiet >= STAGING.restAfter else "pause"

## When the next quiet session will leave for the plaza, or null.
static func next_staging_change(sessions: Array, now: float) -> Variant:
	var next = null
	for s in sessions:
		if staging_mode(s, now) != "pause":
			continue
		var at: float = _quiet_since(s) + STAGING.restAfter
		if next == null or at < next:
			next = at
	return next

static func _hall_half(id: String) -> float:
	return STAGING.hall.docker if id == "docker" else STAGING.hall.half

static func _hall_boxes(providers: Array) -> Array:
	var out := []
	var positions := provider_positions(providers)
	for id in positions:
		out.append({ "id": id, "x": positions[id].x, "z": positions[id].z, "half": _hall_half(id) })
	return out

static func _obstacles(providers: Array) -> Array:
	var out := _hall_boxes(providers)
	out.append({ "id": "", "x": float(STAGING.plaza.x), "z": float(STAGING.plaza.z), "half": STAGING.plaza.half })
	return out

static func rest_spots(providers: Array) -> Array:
	var plaza: Dictionary = STAGING.plaza
	var cx := float(plaza.x)
	var cz := float(plaza.z)
	var boxes := _hall_boxes(providers)
	var spots := []
	var crew_sessions := []
	for p in providers:
		for i in 8:
			crew_sessions.append({ "id": p.id + ":" + str(i), "provider": { "id": p.id }, "createdAt": str(i) })
	var crews := layout_sessions(crew_sessions, providers).values()
	var props := []
	for c in crews:
		for a in ARRANGEMENTS:
			props.append(_prop_at(c, a))
	var far := atan2(CAMERA.offset[0], CAMERA.offset[2]) + PI
	for ring in plaza.rings:
		var radius: float = ring[0]
		var count: int = ring[1]
		for i in count:
			var k := (-(i + 1) >> 1) if i % 2 else (i >> 1)
			var angle := far + k * 2.0 * PI / count
			var x := cx + sin(angle) * radius
			var z := cz + cos(angle) * radius
			if boxes.any(func(b): return absf(x - b.x) < b.half + 1 and absf(z - b.z) < b.half + 1):
				continue
			if crews.any(func(c): return hypot(x - c.x, z - c.z) < 1.1):
				continue
			if props.any(func(p): return hypot(x - p.x, z - p.z) < STAGING.station.half + .4):
				continue
			spots.append({ "x": round3(x), "z": round3(z), "face": round3(atan2(cx - x, cz - z)) })
	return spots

## Where each session goes and what it does there. previous carries the last
## result, so rest spots, like stations, stay put across unrelated changes.
static func stage(sessions: Array, providers: Array, now: float, previous = null) -> Dictionary:
	var slots := layout_sessions(sessions, providers, previous.slots if previous != null else {})
	var spots := rest_spots(providers)
	var sorted := stable_sort(sessions, _by_created)
	var resting := sorted.filter(func(s): return staging_mode(s, now) == "rest")
	var rest := {}
	var taken := {}
	for s in resting:
		var old = previous.rest.get(s.id) if previous != null else null
		if old != null and old < spots.size() and not taken.has(old):
			taken[old] = true
			rest[s.id] = old
	for s in resting:
		if rest.has(s.id):
			continue
		var i := 0
		while taken.has(i):
			i += 1
		taken[i] = true
		rest[s.id] = i
	var places := {}
	for s in sessions:
		var mode := staging_mode(s, now)
		var slot: Dictionary = slots[s.id]
		var spot = spots[rest[s.id]] if mode == "rest" and rest[s.id] < spots.size() else null
		var station := { "x": round3(slot.x), "z": round3(slot.z) }
		if spot != null:
			places[s.id] = { "x": spot.x, "z": spot.z, "face": spot.face, "mode": mode }
		else:
			places[s.id] = { "x": station.x, "z": station.z, "face": station_prop(station, s.id).characterFace, "mode": "pause" if mode == "rest" else mode }
	return { "slots": slots, "rest": rest, "places": places }

static func arrives(session: Dictionary, now: float) -> bool:
	var created = parse_time(session.get("createdAt"))
	return created != null and now - created < STAGING.arrival

static func door_for(session: Dictionary, providers: Array) -> Dictionary:
	var anchor = provider_positions(providers).get(session.provider.id)
	if anchor == null:
		return { "x": float(STAGING.plaza.x), "z": float(STAGING.plaza.z) }
	var out := STAGING.hall.docker if session.provider.id == "docker" else STAGING.door
	return { "x": anchor.x, "z": round3(anchor.z + out) }

## Segment against an axis-aligned square (Liang-Barsky), for points strictly inside.
static func _crosses(a: Dictionary, b: Dictionary, box: Dictionary, half: float) -> bool:
	var dx: float = b.x - a.x
	var dz: float = b.z - a.z
	var t0 := 0.0
	var t1 := 1.0
	for pq in [[-dx, a.x - (box.x - half)], [dx, box.x + half - a.x], [-dz, a.z - (box.z - half)], [dz, box.z + half - a.z]]:
		var p: float = pq[0]
		var q: float = pq[1]
		if p == 0.0:
			if q <= 0.0:
				return false
			continue
		var r := q / p
		if p < 0.0:
			if r > t1:
				return false
			if r > t0:
				t0 = r
		else:
			if r < t0:
				return false
			if r < t1:
				t1 = r
	return t1 - t0 > 1e-6

## The shortest way from a to b round every hall, the centrepiece and every
## station prop; the waypoints after a, ending at b.
static func route(a: Dictionary, b: Dictionary, providers: Array, props := []) -> Array:
	var inside := func(p, box): return absf(p.x - box.x) < box.half - .05 and absf(p.z - box.z) < box.half - .05
	var boxes := _obstacles(providers)
	for p in props:
		var box := { "x": p.x, "z": p.z, "half": STAGING.station.half }
		if not inside.call(a, box) and not inside.call(b, box):
			boxes.append(box)
	var m: float = STAGING.hall.margin
	var blocked := func(p, q): return boxes.any(func(box): return _crosses(p, q, box, box.half - .05))
	if not blocked.call(a, b):
		return [{ "x": b.x, "z": b.z }]
	var nodes := [a, b]
	for box in boxes:
		for s in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			var p := { "x": box.x + s[0] * (box.half + m), "z": box.z + s[1] * (box.half + m) }
			if not boxes.any(func(other): return absf(p.x - other.x) < other.half and absf(p.z - other.z) < other.half):
				nodes.append(p)
	var dist := []
	var from := []
	var done := []
	for i in nodes.size():
		dist.append(INF); from.append(-1); done.append(false)
	dist[0] = 0.0
	while true:
		var u := -1
		for i in nodes.size():
			if not done[i] and dist[i] < INF and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0 or u == 1:
			break
		done[u] = true
		for v in nodes.size():
			if done[v] or blocked.call(nodes[u], nodes[v]):
				continue
			var d: float = dist[u] + hypot(nodes[v].x - nodes[u].x, nodes[v].z - nodes[u].z)
			if d < dist[v] - 1e-9:
				dist[v] = d
				from[v] = u
	if dist[1] == INF:
		return [{ "x": b.x, "z": b.z }]
	var path := []
	var i := 1
	while i > 0:
		path.push_front({ "x": round3(nodes[i].x), "z": round3(nodes[i].z) })
		i = from[i]
	path[path.size() - 1] = { "x": b.x, "z": b.z }
	return path

static func _prop_at(place: Dictionary, arrangement: String) -> Dictionary:
	var turn: float = STAGING.station.turn
	var gap: float = STAGING.station.gap
	var face: float = STAGING.stationFace + (turn if arrangement == "right" else (-turn if arrangement == "left" else 0.0))
	return { "x": round3(place.x + sin(face) * gap), "z": round3(place.z + cos(face) * gap),
		"face": round3(face + PI), "arrangement": arrangement, "characterFace": round3(face) }

static func station_prop(place: Dictionary, id: String) -> Dictionary:
	return _prop_at(place, ARRANGEMENTS[js_hash(id + ":station") % ARRANGEMENTS.size()])

static func hall_activity(sessions: Array, provider_id: String) -> String:
	var working := sessions.filter(func(s): return s.provider.id == provider_id and s.get("status") != "exited" and s.get("activity") == "active").size()
	return "off" if working == 0 else ("low" if working == 1 else "high")

static func look_limits(yard: Dictionary) -> Dictionary:
	var own: Dictionary = yard.get("look", {})
	return { "yaw": minf(STAGING.look.yaw, float(own.get("yaw", INF))), "pitch": minf(STAGING.look.pitch, float(own.get("pitch", INF))),
		"neck": STAGING.look.neck }

static func look_target(session_id: String, places: Dictionary, selected = null) -> Variant:
	var me = places.get(session_id)
	if me == null or (me.mode != "rest" and me.mode != "pause"):
		return null
	var best = null
	var best_distance := INF
	for id in places:
		if id == session_id:
			continue
		var p: Dictionary = places[id]
		var d := hypot(p.x - me.x, p.z - me.z)
		if d > STAGING.look.range:
			continue
		if id == selected:
			return id
		if d < best_distance - 1e-9 or (absf(d - best_distance) <= 1e-9 and best != null and id < best):
			best = id
			best_distance = d
	return best

static func clip_for(id: String, mode: String, n: int) -> String:
	var set: Array = CLIPS.character.get(mode, CLIPS.character.pause) if mode != "walk" else CLIPS.character.pause
	if set.size() == 1:
		return set[0]
	var h := js_hash(id + ":" + mode + ":" + str(n / 3))
	if mode == "work":
		return set[1] if n % 3 == 2 and h % 2 else set[0]
	return set[1 + (h % (set.size() - 1))] if n % 3 == 2 else set[0]

static func helper_offset(i: int, count: int) -> Dictionary:
	var angle := (float(i) / mini(count, 6)) * PI * 2.0
	return { "x": round3(cos(angle) * .82), "z": round3(sin(angle) * .72) }
