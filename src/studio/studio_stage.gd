class_name StudioStage
extends Node3D
## Studio's preview: a plain floor under a world's sun, by day or at dusk,
## with the piece beside the slot's default at a station, or a world's
## companions round a character. The sun's colour and place and the light
## from above are the contract's (YardModel.WORLDS, SUN); there is no scenery.

## Where the stage stands.
const SPOT := Vector3(0, 0, 0)
## How far apart the piece and the default stand.
const APART := 1.0
## Companions as Agent Guild shows them round a character.
const COMPANIONS := YardModel.SHOWN_HELPERS
const COMPANION_SCALE := 0.45
## Whose seeded sequences the stage plays (YardModel.clip_for).
const SEED := "studio"
## A clip blends into the next over this long; companions hover this far up.
const FADE := 0.3
const FLOOR := 0.0
const HOVER := 0.1
const FLOOR_RADIUS := 9.0
const SUN_ENERGY := { "light": 3.2, "dark": 2.2 }
const SKY_ENERGY := { "light": 0.9, "dark": 0.45 }
const EXPOSURE := { "light": 1.15, "dark": 1.05 }
const BACKDROP := { "light": 0.82, "dark": 0.1 }
const GROUND := { "light": 0.5, "dark": 0.32 }

var camera: CameraRig
var world_name := ""
var theme := "light"
var reduced := false
var models: Array[Node3D] = []
## What the models do, as Agent Guild has them do it: a character's walk
## repeating, or a mode's sequence (work, pause, rest, done), each clip
## played once and blended into the next; a companion's clip repeating.
var motion := ""
var _kind := "character"
var _players: Array[AnimationPlayer] = []
var _counts := {}
var _shown := Node3D.new()
var _environment := WorldEnvironment.new()
var _sun := DirectionalLight3D.new()
var _floor := MeshInstance3D.new()
var _stations := {}

func _ready() -> void:
	_environment.environment = Environment.new()
	add_child(_environment)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 40.0
	_sun.shadow_bias = 0.03
	_sun.shadow_normal_bias = 1.2
	_sun.shadow_blur = 1.5
	add_child(_sun)
	var disc := CylinderMesh.new()
	disc.top_radius = FLOOR_RADIUS
	disc.bottom_radius = FLOOR_RADIUS
	disc.height = 0.04
	disc.radial_segments = 96
	_floor.mesh = disc
	_floor.position.y = -0.02
	_floor.material_override = StandardMaterial3D.new()
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor)
	add_child(_shown)

## The world whose light the stage stands in, and the time of day.
func set_world(world: String, next_theme: String) -> void:
	world_name = world
	set_theme(next_theme)

func set_theme(next: String) -> void:
	theme = next
	if world_name == "":
		return
	var world: Dictionary = YardModel.WORLDS[world_name]
	var sky := Color.hex((int(world.hemi) << 8) | 0xff)
	var env := _environment.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = (sky * BACKDROP[theme]).lerp(Color.WHITE if theme == "light" else Color.BLACK, 0.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = sky
	env.ambient_light_energy = SKY_ENERGY[theme]
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = EXPOSURE[theme]
	var s: Array = YardModel.SUN[theme]
	_sun.look_at_from_position(Vector3(s[0], s[1], s[2]), Vector3.ZERO, Vector3.UP)
	_sun.light_color = Color.hex((int(world.sun[theme]) << 8) | 0xff)
	_sun.light_energy = SUN_ENERGY[theme]
	_sun.light_angular_distance = 0.8 if theme == "light" else 1.6
	var ground: StandardMaterial3D = _floor.material_override
	ground.albedo_color = Color(sky * GROUND[theme], 1.0)
	ground.roughness = 0.9

## The models to show (Node3D scenes, outside the tree; the stage frees them):
## for a character, the piece then the default; for companions, a character
## then the four companions, shown six round it as Agent Guild shows them.
func show_models(list: Array, kind: String) -> void:
	clear()
	for m: Node3D in list:
		models.append(m)
	if kind == "character":
		# Side by side at their stations, seen three-quarters from the front:
		# faces show, and their work reaches toward the station beside the view.
		for k in models.size():
			models[k].position = SPOT + Vector3(0, 0, (0.5 - k) * 2.0 * APART)
			models[k].rotation.y = PI / 2.0
			_shown.add_child(models[k])
		_station_for(models)
	else:
		var host: Node3D = models[0]
		host.position = SPOT
		_shown.add_child(host)
		var four := models.slice(1)
		for i in COMPANIONS:
			var copy: Node3D = four[i % four.size()] if i < four.size() else four[i % four.size()].duplicate()
			var offset := YardModel.helper_offset(i, COMPANIONS)
			copy.scale = Vector3.ONE * COMPANION_SCALE
			copy.position = SPOT + Vector3(offset.x, FLOOR + HOVER, offset.z)
			_shown.add_child(copy)
			if i >= four.size():
				models.append(copy)
	if kind != _kind:
		motion = ""
	_kind = kind
	_players.clear()
	for m in models:
		for p: AnimationPlayer in m.find_children("*", "AnimationPlayer", true, false):
			_own_clips(p)
			for clip in p.get_animation_list():
				p.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if kind != "character" or clip == "walk" else Animation.LOOP_NONE
			p.animation_finished.connect(_finished.bind(p))
			_players.append(p)
	# Aimed left of the pair, so they stand in the room the side panel leaves.
	if camera:
		camera.frame(SPOT + Vector3(-0.35, 0.9, 0.5), deg_to_rad(55.0), deg_to_rad(14.0), 4.4)

## Nothing on the stage.
func clear() -> void:
	for child in _shown.get_children():
		child.queue_free()
	models.clear()
	_players.clear()
	_counts.clear()

## A station before each character, scaled to it as Agent Guild scales one.
func _station_for(characters: Array) -> void:
	var asset: String = YardModel.WORLDS[world_name].station.asset
	if not _stations.has(asset):
		var path := StudioArt.model_path(world_name, asset)
		_stations[asset] = load(path) if path != "" else null
	var scene: PackedScene = _stations[asset]
	if scene == null:
		return
	for c: Node3D in characters:
		var yard_extras := YardRig.extras(c)
		var station: Node3D = scene.instantiate()
		var surface := float(yard_extras.get("surface", 0.0))
		var base := float(YardModel.WORLDS[world_name].station.surface)
		station.scale = Vector3.ONE * (surface / base if surface > 0.0 else 1.0)
		station.position = c.position + Vector3(YardModel.STAGING.station.gap, 0, 0)
		station.rotation.y = -PI / 2.0
		_shown.add_child(station)

## The player's clips as copies of its own: a default's are shared with every
## other instance of it, whose clips the stage must never change.
static func _own_clips(player: AnimationPlayer) -> void:
	for name in player.get_animation_library_list():
		var shared := player.get_animation_library(name)
		var own := AnimationLibrary.new()
		for clip in shared.get_animation_list():
			own.add_animation(clip, shared.get_animation(clip).duplicate())
		player.remove_animation_library(name)
		player.add_animation_library(name, own)

## The piece shown at `factor` its made size, at once; its exact fit waits
## until it's saved.
func resize(factor: float) -> void:
	if _kind == "character" and not models.is_empty():
		models[0].scale = Vector3.ONE * factor

## The companions turned `degrees` from as made, at once, until they're made
## again turned.
func turn(degrees: float) -> void:
	if _kind != "character":
		for m in models.slice(1):
			m.rotation.y = deg_to_rad(degrees)

## Every model starts `next`: walk, work, pause, rest or done for a
## character, a clip for companions.
func play(next: String) -> void:
	motion = next
	for p in _players:
		_counts[p] = 0
		_cross(p, _clip(0))

func _clip(n: int) -> String:
	if _kind != "character" or motion == "walk":
		return motion
	return YardModel.clip_for(SEED, motion, n)

func _cross(p: AnimationPlayer, clip: String) -> void:
	if p.has_animation(clip):
		p.play(clip, 0.0 if reduced else FADE)

## A clip played once is over: the sequence's next.
func _finished(_name: StringName, p: AnimationPlayer) -> void:
	_counts[p] = int(_counts.get(p, 0)) + 1
	var next := _clip(_counts[p])
	if next == p.assigned_animation:
		p.stop()
		p.play(next)
	else:
		_cross(p, next)
