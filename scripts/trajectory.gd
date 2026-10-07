extends Node3D
class_name TurnViz

# Turn-geometry overlay drawn in the CAR'S LOCAL frame (this node is a child of the
# car), so it shares the car's exact transform and can never drift from the wheels.
# The instantaneous turning circle is a car-relative object, so this is also correct.

const GROUND_Y := 0.03
const SEGMENTS := 96

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _icz_marker: MeshInstance3D
var _show_circles := false

const C_ICZ := Color(0.9, 0.1, 0.9)
const C_OUTER := Color(1.0, 0.25, 0.25)
const C_INNER := Color(0.25, 0.75, 1.0)
const C_ARC_OUTER := Color(1.0, 0.5, 0.2)
const C_ARC_INNER := Color(0.4, 0.9, 0.5)
const C_SPOKE := Color(0.8, 0.8, 0.8, 0.55)
const C_TIRE := Color(1.0, 1.0, 0.3)

func _build() -> void:
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	_instance.material_override = mat
	add_child(_instance)

	_icz_marker = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.28
	sph.height = 0.56
	_icz_marker.mesh = sph
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = C_ICZ
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icz_marker.material_override = mmat
	_icz_marker.visible = false
	add_child(_icz_marker)

func set_show_circles(v: bool) -> void:
	_show_circles = v

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, GROUND_Y, v.z)

func update(car: AckermannCar) -> void:
	_mesh.clear_surfaces()
	var r := car.turning_radius
	if is_inf(r) or absf(r) > 200.0:
		_icz_marker.visible = false
		return

	var l := car.wheel_base
	var hw := car.wheel_track * 0.5
	# everything below is in the car's local frame: rear axle at origin, nose = -Z,
	# right = +X. The ICZ lies on the rear-axle line at (r, 0, 0).
	var icz := Vector3(r, 0.0, 0.0)
	_icz_marker.visible = true
	_icz_marker.position = Vector3(r, 0.06, 0.0)

	var fl := Vector3(-hw, 0.0, -l)
	var fr := Vector3(hw, 0.0, -l)
	var rl := Vector3(-hw, 0.0, 0.0)
	var rr := Vector3(hw, 0.0, 0.0)

	var d_fl := Vector2(fl.x - icz.x, fl.z - icz.z).length()
	var d_fr := Vector2(fr.x - icz.x, fr.z - icz.z).length()
	var d_rl := Vector2(rl.x - icz.x, rl.z - icz.z).length()
	var d_rr := Vector2(rr.x - icz.x, rr.z - icz.z).length()
	var r_max := maxf(maxf(d_fl, d_fr), maxf(d_rl, d_rr))
	var r_min := minf(minf(d_fl, d_fr), minf(d_rl, d_rr))

	var icz0 := _flat(icz)
	var max_w := fl
	var min_w := rl
	if d_fr >= d_fl:
		max_w = fr
	if d_rr <= d_rl:
		min_w = rr

	# radius lines ICZ -> outer wheel and ICZ -> inner wheel
	_add_line(icz0, _flat(max_w), C_OUTER)
	_add_line(icz0, _flat(min_w), C_INNER)

	# faint ICZ -> every-wheel spokes + ground-contact crosses (pinned to tires)
	_add_line(icz0, _flat(fl), C_SPOKE)
	_add_line(icz0, _flat(fr), C_SPOKE)
	_add_line(icz0, _flat(rl), C_SPOKE)
	_add_line(icz0, _flat(rr), C_SPOKE)
	_add_cross(_flat(fl), C_TIRE)
	_add_cross(_flat(fr), C_TIRE)
	_add_cross(_flat(rl), C_TIRE)
	_add_cross(_flat(rr), C_TIRE)

	# turning circles (or a short arc whose length is ~3x car length to convey curvature)
	var car_len := car.overall_length
	var arc_len := 3.0 * car_len
	var sweep_out := clampf(arc_len / r_max, 0.15, PI)
	var sweep_in := clampf(arc_len / r_min, 0.15, PI)
	var ang_out := atan2(max_w.z - icz.z, max_w.x - icz.x)
	var ang_in := atan2(min_w.z - icz.z, min_w.x - icz.x)
	if _show_circles:
		_add_arc(icz0, r_max, 0.0, TAU, C_ARC_OUTER)
		_add_arc(icz0, r_min, 0.0, TAU, C_ARC_INNER)
	else:
		_add_arc(icz0, r_max, ang_out - sweep_out * 0.5, ang_out + sweep_out * 0.5, C_ARC_OUTER)
		_add_arc(icz0, r_min, ang_in - sweep_in * 0.5, ang_in + sweep_in * 0.5, C_ARC_INNER)

func _add_line(a: Vector3, b: Vector3, col: Color) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, null)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(b)
	_mesh.surface_end()

func _add_cross(p: Vector3, col: Color) -> void:
	var s := 0.22
	var y := GROUND_Y + 0.01
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, null)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(Vector3(p.x - s, y, p.z))
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(Vector3(p.x + s, y, p.z))
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(Vector3(p.x, y, p.z - s))
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(Vector3(p.x, y, p.z + s))
	_mesh.surface_end()

func _add_arc(center: Vector3, radius: float, from: float, to: float, col: Color) -> void:
	var n := int(ceil(SEGMENTS * (to - from) / TAU))
	n = clampi(n, 2, SEGMENTS)
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, null)
	for i in range(n + 1):
		var t := from + (to - from) * (float(i) / float(n))
		var p := center + Vector3(cos(t) * radius, 0.0, sin(t) * radius)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(p)
	_mesh.surface_end()
