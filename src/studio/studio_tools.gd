class_name StudioTools
## What a slot default holds, and whether a piece may carry it. A default's
## tool is part of its own mesh, weighted to a Prop bone. Studio never copies
## one on its own: it offers a tool only when it comes away cleanly (every
## triangle of it on the Prop bone alone, none sharing a vertex with the
## body) and its redistribution is permitted; otherwise the piece's hands are
## empty, and Studio says so. Plain data, so any thread.

## Defaults whose held tools may be carried by pieces, by model name.
const SHAREABLE := {}

## { Left/Right: { clean: bool, surface } } for each hand the default holds
## something in; `surface` is the tool alone, ready to carry, when clean.
## `default` is StudioSource.read of the default model.
static func held(default: Dictionary) -> Dictionary:
	var rig: Dictionary = default.rig
	var out := {}
	for side in ["Left", "Right"]:
		var prop: int = rig.names.find("Prop" + side)
		if prop < 0:
			continue
		var faces := 0
		var mixed := 0
		var tool := { "verts": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(), "indices": PackedInt32Array() }
		var looks := []
		for s in default.surfaces:
			var on_prop := PackedByteArray()
			on_prop.resize(s.verts.size())
			for v in s.verts.size():
				var all := 0.0
				var mine := 0.0
				for k in s.per:
					all += s.weights[v * s.per + k]
					if s.bones[v * s.per + k] == prop:
						mine += s.weights[v * s.per + k]
				on_prop[v] = 2 if all > 0.0 and mine >= all * 0.999 else (1 if mine > 0.0 else 0)
			var renumber := {}
			for t in range(0, s.indices.size(), 3):
				var corners := [s.indices[t], s.indices[t + 1], s.indices[t + 2]]
				var kinds := corners.map(func(c): return on_prop[c])
				if kinds.all(func(k): return k == 0):
					continue
				if not kinds.all(func(k): return k == 2):
					mixed += 1
					continue
				faces += 1
				for c in corners:
					if not renumber.has(c):
						renumber[c] = tool.verts.size()
						tool.verts.append(s.verts[c])
						tool.normals.append(s.normals[c] if not s.normals.is_empty() else Vector3.UP)
						tool.uvs.append(s.uvs[c] if not s.uvs.is_empty() else Vector2.ZERO)
					tool.indices.append(renumber[c])
				if not s.look in looks:
					looks.append(s.look)
			# A tool's vertex the body also uses means the two are one piece of mesh.
			for t in range(0, s.indices.size(), 3):
				var corners := [s.indices[t], s.indices[t + 1], s.indices[t + 2]]
				if corners.any(func(c): return on_prop[c] == 2) and corners.any(func(c): return on_prop[c] == 0):
					mixed += 1
		if faces + mixed == 0:
			continue
		tool.look = looks[0] if looks.size() == 1 else null
		out[side] = { "clean": mixed == 0 and looks.size() == 1, "surface": tool }
	return out

## The default's tools carried onto the piece where they may be, and in words
## what happened to each. `name` is the default model's; `permitted` stands
## for SHAREABLE.
static func carry(piece: Dictionary, default: Dictionary, held_tools: Dictionary, name: String, permitted := SHAREABLE) -> Array:
	var notes := []
	var mine := StudioRig.rest_globals(piece.rig)
	var theirs := StudioRig.rest_globals(default.rig)
	for side in held_tools:
		var hand := "left" if side == "Left" else "right"
		if not held_tools[side].clean:
			notes.append("The character it replaces holds a tool in its %s hand that is part of its own mesh, so this piece's %s hand is empty." % [hand, hand])
			continue
		if not permitted.has(name):
			notes.append("The tool in the %s hand of the character it replaces isn't shared with pieces, so this piece's %s hand is empty." % [hand, hand])
			continue
		var prop: int = piece.rig.names.find("Prop" + side)
		var move: Transform3D = mine[prop] * theirs[default.rig.names.find("Prop" + side)].affine_inverse()
		var tool: Dictionary = held_tools[side].surface.duplicate()
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		for v in tool.verts:
			verts.append(move * v)
		for n in tool.normals:
			normals.append((move.basis * n).normalized())
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for v in verts.size():
			bones.append_array([prop, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
		piece.surfaces.append(tool.merged({ "verts": verts, "normals": normals, "bones": bones, "weights": weights }, true))
		notes.append("It holds the tool of the character it replaces in its %s hand." % hand)
	return notes
