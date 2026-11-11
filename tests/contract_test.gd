extends RefCounted
## Reproduces every golden vector in agent-guild's tests/fixtures/yard-choreography.json
## (its scripts/yard-golden.mjs), read from the checkout AGENT_GUILD_CHECKOUT names,
## with the GDScript port. Numbers
## must agree to within reading the fixture's decimal text (1e-9): every
## contract value is rounded to the millimetre or exact, so any real
## disagreement is far larger.

const FIXTURE := "tests/fixtures/yard-choreography.json"

var failures := []

func run(_tree: SceneTree) -> Array:
	var path := OS.get_environment("AGENT_GUILD_CHECKOUT").path_join(FIXTURE)
	if not FileAccess.file_exists(path):
		return ["Set AGENT_GUILD_CHECKOUT to an Agent Guild checkout containing %s." % FIXTURE]
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var M := YardModel
	var providers := (golden.providers as Array).map(func(id): return { "id": id })
	var now: float = M.parse_time(golden.now)
	var sessions: Array = golden.sessions
	var first := M.stage(sessions, providers, now)

	var hashes := {}
	for value in golden.hash:
		hashes[value] = M.js_hash(value)
	same("hash", hashes, golden.hash)
	same("restSpots", M.rest_spots(providers), golden.restSpots)
	same("places", first.places, golden.places)
	same("nextChange", M.iso_time(M.next_staging_change(sessions, now)), golden.nextChange)

	var later_now: float = M.parse_time(golden.after.now)
	same("after.now", later_now, now + 1000)
	var second := M.stage(golden.after.sessions, providers, later_now, first)
	same("after.places", second.places, golden.after.places)

	same("arrives", [0, 14999, 15000, 600000].map(func(ms): return M.arrives({ "createdAt": M.iso_time(now - ms) }, now)), golden.arrives)
	var doors := {}
	for id in golden.doors:
		doors[id] = M.door_for({ "provider": { "id": id } }, providers)
	same("doors", doors, golden.doors)

	var routes := (golden.routes as Array).map(func(r): return { "from": r.from, "to": r.to, "path": M.route(r.from, r.to, providers) })
	same("routes", routes, golden.routes)

	var props := {}
	for id in first.slots:
		var slot: Dictionary = first.slots[id]
		props[id] = M.station_prop({ "x": M.round3(slot.x), "z": M.round3(slot.z) }, id)
	same("stationProps", props, golden.stationProps)
	var prop_routes := []
	var starts := [first.places["anthropic-2"], first.places["xai-1"], { "x": -12.0, "z": 6.4 }, first.places["shell-3"]]
	var ends := [first.places["openai-0"], { "x": 0.0, "z": 4.0 }, { "x": -4.0, "z": 6.4 }, first.places["docker-1"]]
	for i in starts.size():
		var a := { "x": starts[i].x, "z": starts[i].z }
		var b := { "x": ends[i].x, "z": ends[i].z }
		prop_routes.append({ "from": a, "to": b, "path": M.route(a, b, providers, props.values()) })
	same("propRoutes", prop_routes, golden.propRoutes)

	var activity := {}
	for id in golden.providers + ["github"]:
		activity[id] = M.hall_activity(sessions, id)
	same("hallActivity", activity, golden.hallActivity)
	for selected in [null, "openai-1"]:
		var looks := {}
		for s in sessions:
			looks[s.id] = M.look_target(s.id, first.places, selected)
		same("lookTargets" + ("Selected" if selected else ""), looks, golden["lookTargets" + ("Selected" if selected else "")])

	var clips := {}
	for key in golden.clips:
		var parts: PackedStringArray = key.split(":")
		var seq := []
		for n in 12:
			seq.append(M.clip_for(parts[0], parts[1], n))
		clips[key] = seq
	same("clips", clips, golden.clips)

	var covered := ["providers", "now", "hash", "restSpots", "sessions", "places", "nextChange", "after", "arrives", "doors", "routes", "propRoutes", "stationProps", "hallActivity", "lookTargets", "lookTargetsSelected", "clips"]
	for key in golden:
		if not covered.has(key):
			failures.append("the fixture has a section this test does not check: " + key)
	return failures

func same(what: String, got, want) -> void:
	var problem := _diff(got, want, what)
	if problem != "":
		failures.append(problem)

func _diff(got, want, at: String) -> String:
	if (got is float or got is int) and (want is float or want is int):
		return "" if absf(float(got) - float(want)) <= 1e-9 else "%s: %s, want %s" % [at, got, want]
	if want is Dictionary:
		if not got is Dictionary:
			return "%s: %s, want an object" % [at, got]
		if got.keys() != want.keys():
			return "%s: keys %s, want %s" % [at, got.keys(), want.keys()]
		for k in want:
			var d := _diff(got[k], want[k], "%s.%s" % [at, k])
			if d != "":
				return d
		return ""
	if want is Array:
		if not got is Array or got.size() != want.size():
			return "%s: %s, want %s" % [at, got, want]
		for i in want.size():
			var d := _diff(got[i], want[i], "%s[%d]" % [at, i])
			if d != "":
				return d
		return ""
	if typeof(got) != typeof(want) or got != want:
		return "%s: %s, want %s" % [at, got, want]
	return ""
