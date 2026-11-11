class_name PiecePreview
extends SubViewport

const SIZE := Vector2i(768, 768)
const BACKDROP := Color("#3b4048")
const POSE := { "character": "idle_0", "companion": "idle" }
const PITCH := deg_to_rad(-10.0)
const FILL := 0.85
const GAP := 0.25

var camera: Camera3D
var models: Array[Node3D] = []

func stage(scenes: Array, kind: String) -> void:
	size = SIZE
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	key.light_energy = 1.4
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(150), 0)
	rim.light_energy = 0.6
	add_child(rim)
	var cell := Vector2.ZERO
	var boxes := []
	for scene: PackedScene in scenes:
		var model: Node3D = scene.instantiate()
		add_child(model)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty() and players.front().has_animation(POSE[kind]):
			players.front().play(POSE[kind])
			players.front().seek(0.0, true)
		var box := bounds_of(model)
		boxes.append(box)
		cell = cell.max(Vector2(box.size.x, box.size.y))
		models.append(model)
	var columns := 1 if models.size() == 1 else 2
	for i in models.size():
		var box: AABB = boxes[i]
		var at := Vector3((i % columns - (columns - 1) * 0.5) * (cell.x + GAP), -(i / columns) * (cell.y + GAP), 0)
		models[i].position = at - Vector3(box.get_center().x, box.position.y, box.get_center().z)
	camera = Camera3D.new()
	add_child(camera)
	_frame()

func capture() -> Image:
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := get_texture().get_image()
	return image if image != null and not image.is_empty() else null

static func bounds_of(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var part := mesh.global_transform * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box

func _frame() -> void:
	var box := AABB()
	for i in models.size():
		box = bounds_of(models[i]) if i == 0 else box.merge(bounds_of(models[i]))
	var center := box.get_center()
	var basis := Basis.from_euler(Vector3(PITCH, 0, 0))
	var tan_v := tan(deg_to_rad(camera.fov) * 0.5) * FILL
	var tan_h := tan_v * float(SIZE.x) / SIZE.y
	var distance := 0.0
	for c in 8:
		var local := basis.inverse() * (box.get_endpoint(c) - center)
		distance = maxf(distance, local.z + maxf(absf(local.x) / tan_h, absf(local.y) / tan_v))
	camera.transform = Transform3D(basis, center + basis.z * distance)
	camera.near = maxf(0.01, distance * 0.05)
	camera.far = distance * 4.0
