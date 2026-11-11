class_name CameraRig
extends Camera3D
## A free camera over the play area: it pans within CAMERA.pan, orbits all
## the way round, tilts between a low and a steep view, and zooms over the
## web Yard's range. It starts on the web Yard's overview, and `parity`
## switches to the web's exact orthographic view for side-by-side captures.

const FOV := 30.0
const PITCH := Vector2(deg_to_rad(18.0), deg_to_rad(72.0))

var parity := false
var target := Vector3(0, 1, 0)
var yaw := 0.0
var pitch := 0.0
var zoom := 1.02
var _goal_target := target
var _goal_yaw := 0.0
var _goal_pitch := 0.0
var _goal_zoom := zoom

func _ready() -> void:
	fov = FOV
	near = 0.1
	far = 600.0
	overview(true)

## The web Yard's view: along CAMERA.offset to its target, at the overview zoom.
func overview(at_once := false) -> void:
	var o: Array = YardModel.CAMERA.offset
	_goal_target = Vector3(YardModel.CAMERA.target[0], YardModel.CAMERA.target[1], YardModel.CAMERA.target[2])
	_goal_yaw = atan2(o[0], o[2])
	_goal_pitch = atan2(o[1], sqrt(o[0] * o[0] + o[2] * o[2]))
	_goal_zoom = maxf(YardModel.CAMERA.zoom.overview, _min_zoom())
	if at_once:
		_snap()

## Puts the camera at once over a point, turned and tilted, at a zoom; free of the pan bounds.
func frame(point: Vector3, at_yaw: float, at_pitch: float, at_zoom: float) -> void:
	_goal_target = point
	_goal_yaw = at_yaw
	_goal_pitch = at_pitch
	_goal_zoom = at_zoom
	_snap()

## Where the camera is going: { target, yaw, pitch, zoom }, for `glide` to return to.
func goal() -> Dictionary:
	return { "target": _goal_target, "yaw": _goal_yaw, "pitch": _goal_pitch, "zoom": _goal_zoom }

## Eases to a view `goal` gave or a caller made, free of the pan bounds and zoom range.
func glide(view: Dictionary, at_once := false) -> void:
	_goal_target = view.target
	_goal_yaw = view.yaw
	_goal_pitch = view.pitch
	_goal_zoom = view.zoom
	if at_once:
		_snap()

func focus(point: Vector3) -> void:
	_goal_target = _bound(Vector3(point.x, 1, point.z))
	_goal_zoom = maxf(YardModel.CAMERA.zoom.focus, _min_zoom())

func pan(screen_delta: Vector2) -> void:
	var height := _view_height()
	var px := height / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var ahead := Vector3(-sin(yaw), 0, -cos(yaw))
	_goal_target = _bound(_goal_target - right * screen_delta.x * px + ahead * screen_delta.y * px / sin(maxf(pitch, 0.3)))

func orbit(dyaw: float, dpitch: float) -> void:
	_goal_yaw += dyaw
	_goal_pitch = clampf(_goal_pitch + dpitch, PITCH.x, PITCH.y)

func zoom_by(factor: float) -> void:
	_goal_zoom = clampf(_goal_zoom * factor, _min_zoom(), YardModel.CAMERA.zoom.max)

## Whether the camera has come to rest on where it was sent.
func settled() -> bool:
	return target.distance_to(_goal_target) < 0.01 and absf(angle_difference(yaw, _goal_yaw)) < 0.001 and absf(pitch - _goal_pitch) < 0.001 and absf(zoom - _goal_zoom) < 0.001

func _min_zoom() -> float:
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	return YardModel.min_zoom(size.x / maxf(size.y, 1.0))

func _bound(p: Vector3) -> Vector3:
	var c := YardModel.clamp_pan({ "x": p.x, "z": p.z })
	return Vector3(c.x, p.y, c.z)

func _view_height() -> float:
	return float(YardModel.CAMERA.height) / zoom

func _snap() -> void:
	target = _goal_target
	yaw = _goal_yaw
	pitch = _goal_pitch
	zoom = _goal_zoom
	_apply()

func _process(dt: float) -> void:
	var k := 1.0 - exp(-10.0 * dt)
	target = target.lerp(_goal_target, k)
	yaw = lerp_angle(yaw, _goal_yaw, k)
	pitch = lerpf(pitch, _goal_pitch, k)
	zoom = lerpf(zoom, _goal_zoom, k)
	_apply()

func _apply() -> void:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	if parity:
		projection = PROJECTION_ORTHOGONAL
		size = _view_height()
		# Where the web stands it: farther off, the dusk fog fills the view.
		var o: Array = YardModel.CAMERA.offset
		global_position = target + Vector3(o[0], o[1], o[2])
	else:
		projection = PROJECTION_PERSPECTIVE
		var distance := _view_height() / (2.0 * tan(deg_to_rad(FOV) / 2.0))
		global_position = target + dir * distance
	look_at(target, Vector3.UP)
