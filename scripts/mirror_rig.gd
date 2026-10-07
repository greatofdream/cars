extends Node3D
class_name MirrorRig

# Three rear-view mirrors (center / left / right). Each is a SubViewport + Camera3D
# kept in a fixed pose relative to the car body. The cameras render the same World3D
# as the main view, so the mirrors show the actual course and car behind you.

const VP_W := 480
const VP_H := 300

const CENTER := 0
const LEFT := 1
const RIGHT := 2

var _cams: Array[Camera3D] = []
var _vps: Array[SubViewport] = []

var _base_pos: Array[Vector3] = []
var _base_yaw: Array[float] = []
var _yaw: Array[float] = []     # driver-adjustable outward spread (rad)
var _pitch: Array[float] = []   # driver-adjustable vertical aim (rad)

func _build(car: AckermannCar) -> void:
	var hw := car.track_width * 0.5
	# name             local mount pos                              look-back yaw, spread, pitch, fov
	_add(Vector3(0.0, 1.34, -car.wheel_base * 0.20), PI, 0.0, -0.05, 70.0)                    # center
	# Side mirrors mounted beside the driver (front-door / A-pillar), not out at the nose.
	# If they sit too far forward + high, a back-and-inward look frames the whole (transparent)
	# greenhouse = you "see into the cockpit". Pull them back, out, and reduce inward yaw + FOV.
	_add(Vector3(-(hw + 0.18), 1.10, -car.wheel_base * 0.50), PI, 0.20, -0.06, 90.0)          # left
	_add(Vector3((hw + 0.18), 1.10, -car.wheel_base * 0.50), PI, -0.20, -0.20, 90.0)          # right

func _add(pos: Vector3, base_yaw: float, spread: float, pitch0: float, fov: float) -> void:
	_base_pos.append(pos)
	_base_yaw.append(base_yaw)
	_yaw.append(spread)
	_pitch.append(pitch0)

	var vp := SubViewport.new()
	vp.size = Vector2i(VP_W, VP_H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_vps.append(vp)

	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	cam.far = 400.0
	cam.top_level = true
	vp.add_child(cam)
	cam.make_current()
	_cams.append(cam)

func _sync(car: AckermannCar) -> void:
	var ct := car.global_transform
	for i in _cams.size():
		var b := ct.basis * Basis.from_euler(Vector3(_pitch[i], _base_yaw[i] + _yaw[i], 0.0))
		var origin := ct.origin + ct.basis * _base_pos[i]
		_cams[i].global_transform = Transform3D(b.orthonormalized(), origin)

func texture(idx: int) -> Texture2D:
	return _vps[idx].get_texture()

func is_convex(idx: int) -> bool:
	return idx != CENTER

func adjust_yaw(idx: int, d: float) -> void:
	_yaw[idx] = clampf(_yaw[idx] + d, -1.3, 1.3)

func adjust_pitch(idx: int, d: float) -> void:
	_pitch[idx] = clampf(_pitch[idx] + d, -0.7, 0.5)
