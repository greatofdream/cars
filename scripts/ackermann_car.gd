extends Node3D
class_name AckermannCar

# Low-speed Ackermann kinematic car (no tire slip / no suspension).
# Reference point = rear-axle center (node origin). Vehicle forward = -Z (Godot convention).

@export var wheel_base: float = 2.51         # L, rear axle -> front axle (m) - Jetta coach car
@export var track_width: float = 1.69        # W, body/outline width (m) - exam-car width
@export var wheel_track: float = 1.42        # left<->right TYRE centre spacing (m) ~ Jetta track
@export var overall_length: float = 4.41     # total body length (m) - exam-car length
@export var rear_overhang: float = 0.9       # rear bumper behind rear axle (m)
@export var max_speed: float = 8.0           # forward speed cap (m/s)
@export var max_reverse_speed: float = 4.0
@export var accel: float = 6.0
@export var brake_decel: float = 10.0
@export var coast_decel: float = 3.0
@export var max_steer_deg: float = 34.0      # mean front-wheel steer angle limit
@export var steer_rate_deg: float = 90.0     # how fast the wheel turns toward target
@export var steer_sign: float = 1.0          # flip to -1.0 if steering feels inverted
@export var idle_creep_speed: float = 0.0    # clutch-walk speed with no gas/brake (m/s); 0 = stays still
@export var body_color: Color = Color(0.85, 0.25, 0.2)

var speed: float = 0.0            # signed longitudinal speed at rear axle
var steer: float = 0.0           # current mean front steer angle (rad), signed
var turning_radius: float = INF # rear-axle turning radius (m), signed
var ui_steer_deg: float = 0.0   # held front-wheel angle (deg) set by the on-screen steering wheel

# pedal state (0..1), smoothed like a real foot pressing a pedal
var throttle: float = 0.0
var brake: float = 0.0

# automatic-style gear selector, ordered so Q/E can step down/up through it
enum Gear { P, R, N, D }
var gear: int = Gear.D

const PEDAL_RATE := 3.0          # how fast a pedal reaches full travel (per second)

var _hub_fl: Node3D
var _hub_fr: Node3D
var _roll_nodes: Array[Node3D] = []
var _front_hubs: Array[Node3D] = []
var _cabin: Node3D
var _cockpit: Node3D

func _build() -> void:
	var hw := wheel_track * 0.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color

	# Body as a CSG box with a half-cylindrical wheel arch scooped out at each tyre,
	# so the tyres sit in wells instead of intersecting the solid body. Combiner is at
	# the car origin (rear-axle centre); nose = -Z, rear bumper sits rear_overhang behind origin.
	var comb := CSGCombiner3D.new()
	comb.material_override = mat
	add_child(comb)

	var box := CSGBox3D.new()
	box.size = Vector3(track_width, 0.55, overall_length)
	box.position = Vector3(0, 0.55, rear_overhang - overall_length * 0.5)
	box.material_override = mat
	comb.add_child(box)

	# one subtract-cylinder per wheel: axis along X (local Y rotated to world X),
	# centered on the body's bottom edge so only its top half bites in -> a half-cylinder arch
	var arch_r := 0.37
	var arch_w := 0.28
	for z in [0.0, -wheel_base]:
		for side in [-1.0, 1.0]:
			var c := CSGCylinder3D.new()
			c.radius = arch_r
			c.height = arch_w
			c.rotation.z = PI / 2.0
			c.position = Vector3(float(side) * hw, 0.275, float(z))
			c.operation = 2  # CSG Operation: 0=union, 1=intersection, 2=subtract
			comb.add_child(c)

	_build_cabin()
	_build_doors()
	_build_cockpit()

	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.08, 0.08, 0.08)

	# shared fake-contact-shadow material (grounds the car in the perspective view)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smat.albedo_color = Color(0, 0, 0, 0.30)

	var shadow_body := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(track_width + 0.4, overall_length + 0.3)
	shadow_body.mesh = sq
	shadow_body.rotation.x = -PI / 2.0
	shadow_body.position = Vector3(0, 0.016, rear_overhang - overall_length * 0.5)
	shadow_body.material_override = smat
	add_child(shadow_body)

	var layout := [
		{"x": -hw, "z": 0.0, "front": false, "key": "rl"},
		{"x":  hw, "z": 0.0, "front": false, "key": "rr"},
		{"x": -hw, "z": -wheel_base, "front": true, "key": "fl"},
		{"x":  hw, "z": -wheel_base, "front": true, "key": "fr"},
	]
	for s in layout:
		var hub := Node3D.new()
		hub.position = Vector3(float(s["x"]), 0.30, float(s["z"]))
		var roll := Node3D.new()
		var mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.height = 0.185
		cyl.top_radius = 0.30
		cyl.bottom_radius = 0.30
		mesh.mesh = cyl
		mesh.material_override = wmat
		mesh.rotation.z = PI / 2.0    # axle now along local X
		roll.add_child(mesh)
		hub.add_child(roll)
		add_child(hub)
		_roll_nodes.append(roll)
		# per-wheel contact disc: if it doesn't meet the tire bottom, the gap is real
		var disc := MeshInstance3D.new()
		var dcm := CylinderMesh.new()
		dcm.height = 0.01
		dcm.top_radius = 0.24
		dcm.bottom_radius = 0.24
		disc.mesh = dcm
		disc.position = Vector3(float(s["x"]), 0.02, float(s["z"]))
		var dmat := StandardMaterial3D.new()
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.albedo_color = Color(0, 0, 0, 0.35)
		disc.material_override = dmat
		add_child(disc)
		if bool(s["front"]):
			_front_hubs.append(hub)
			if float(s["x"]) < 0.0:
				_hub_fl = hub
			else:
				_hub_fr = hub

func tick(delta: float) -> void:
	_read_input(delta)
	_integrate(delta)
	_spin_wheels(delta)

# Greenhouse: a trapezoidal prism (front + rear glass raked, roof shorter than the
# belt line), interior hollow, sides filled with glass. Visible in every view.
func _build_cabin() -> void:
	_cabin = Node3D.new()
	add_child(_cabin)

	var y0 := 0.82                       # floor of the glasshouse (sits on the body top)
	var y1 := 1.40                       # roof height
	var halfb := track_width * 0.50       # greenhouse base half-width (belt line = body edge, flush)
	var halft := track_width * 0.42       # roof half-width (narrower -> smooth tumblehome taper)
	var zbf := -wheel_base * 0.80        # windshield base (A-pillar): FWD dash-to-axle ~0.5 m behind front wheel
	var zbr := -wheel_base * 0.02        # rear-window base - just AHEAD of the rear axle, so the
										 # rear wheel sits under the quarter panel, not under the door
	var rake := wheel_base * 0.15        # how far the roof rakes inward at each end
	var ztf := zbf + rake                # roof front edge
	var ztr := zbr - rake                # roof rear edge
	var zb := (zbf + zbr) * 0.5          # B-pillar base (mid belt line)
	var ztb := (ztf + ztr) * 0.5         # B-pillar top (mid roof rail)

	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.7, 0.85, 0.32)
	glass.roughness = 0.1
	glass.metallic = 0.4
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.1, 0.11, 0.13)
	frame.cull_mode = BaseMaterial3D.CULL_DISABLED

	# four glass surfaces. Base (belt line) is flush with the body shoulder; the roof
	# tapers inward (tumblehome) so the side profile rises smoothly like a real car,
	# instead of a narrow glass box sitting on a wide body (which made a visible ledge).
	_add_panel(_cabin, [_v(-halfb, y0, zbf), _v(halfb, y0, zbf), _v(halft, y1, ztf), _v(-halft, y1, ztf)], glass)  # windshield
	_add_panel(_cabin, [_v(-halfb, y0, zbr), _v(halfb, y0, zbr), _v(halft, y1, ztr), _v(-halft, y1, ztr)], glass)   # rear window
	# sides split into front-door + rear-door panes so the B-pillar reads as a real division
	_add_panel(_cabin, [_v(-halfb, y0, zbf), _v(-halfb, y0, zb), _v(-halft, y1, ztb), _v(-halft, y1, ztf)], glass)  # left front
	_add_panel(_cabin, [_v(-halfb, y0, zb), _v(-halfb, y0, zbr), _v(-halft, y1, ztr), _v(-halft, y1, ztb)], glass)   # left rear
	_add_panel(_cabin, [_v(halfb, y0, zbf), _v(halfb, y0, zb), _v(halft, y1, ztb), _v(halft, y1, ztf)], glass)       # right front
	_add_panel(_cabin, [_v(halfb, y0, zb), _v(halfb, y0, zbr), _v(halft, y1, ztr), _v(halft, y1, ztb)], glass)       # right rear

	# solid roof panel (opaque, reads as the top from outside)
	_add_panel(_cabin, [_v(-halft, y1, ztf), _v(halft, y1, ztf), _v(halft, y1, ztr), _v(-halft, y1, ztr)], frame)

	# pillars + roof rails tracing the trapezoid silhouette (A/B/C lean inward toward the roof)
	var t := 0.05
	_add_bar(_cabin, _v(-halfb, y0, zbf), _v(-halft, y1, ztf), t, frame)   # A-pillar L
	_add_bar(_cabin, _v(halfb, y0, zbf), _v(halft, y1, ztf), t, frame)     # A-pillar R
	_add_bar(_cabin, _v(-halfb, y0, zbr), _v(-halft, y1, ztr), t, frame)   # C-pillar L
	_add_bar(_cabin, _v(halfb, y0, zbr), _v(halft, y1, ztr), t, frame)     # C-pillar R
	_add_bar(_cabin, _v(-halft, y1, ztf), _v(-halft, y1, ztr), t, frame)   # roof rail L
	_add_bar(_cabin, _v(halft, y1, ztf), _v(halft, y1, ztr), t, frame)     # roof rail R
	_add_bar(_cabin, _v(-halfb, y0, zb), _v(-halft, y1, ztb), t, frame)    # B-pillar L
	_add_bar(_cabin, _v(halfb, y0, zb), _v(halft, y1, ztb), t, frame)      # B-pillar R

# Door skin on the body sides: vertical shut-lines (front door / door split / rear door)
# plus a top belt (window-sill) line and a bottom rocker-sill line. Sits on the lower
# opaque body, aligned to the pillars.
func _build_doors() -> void:
	var d := Node3D.new()
	add_child(d)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.06, 0.06, 0.07)
	trim.cull_mode = BaseMaterial3D.CULL_DISABLED

	var x := track_width * 0.5
	var zf := -wheel_base * 0.80    # front-door leading edge (below A-pillar base)
	var zm := -wheel_base * 0.41    # front/rear door split (below B-pillar base)
	var zr := -wheel_base * 0.02    # rear-door trailing edge (below C-pillar base, ahead of rear wheel)
	for sx in [-x, x]:
		for sz in [zf, zm, zr]:
			_add_bar(d, _v(float(sx), 0.40, float(sz)), _v(float(sx), 0.82, float(sz)), 0.016, trim)
		_add_bar(d, _v(float(sx), 0.82, zf), _v(float(sx), 0.82, zr), 0.014, trim)  # belt (window-sill) line
		_add_bar(d, _v(float(sx), 0.40, zf), _v(float(sx), 0.40, zr), 0.014, trim)  # door bottom (rocker-sill) line

# Cockpit-only extras shown in the driver view (the greenhouse itself is always visible).
func _build_cockpit() -> void:
	_cockpit = Node3D.new()
	_cockpit.visible = false
	add_child(_cockpit)

	var half := track_width * 0.42
	var zbf := -wheel_base * 0.70

	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.13, 0.14, 0.17)
	trim.cull_mode = BaseMaterial3D.CULL_DISABLED

	# steering hint: a thin ring in front of the driver (kept; not a block)
	var wheel := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.16
	tor.outer_radius = 0.21
	wheel.mesh = tor
	wheel.material_override = trim
	wheel.position = Vector3(-half * 0.55, 0.98, zbf + 0.5)
	wheel.rotation.x = -1.1
	_cockpit.add_child(wheel)

func _v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)

func _add_panel(parent: Node, pts_in: Array, mat: Material) -> void:
	var p := PackedVector3Array(pts_in)
	var n := (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	for i: int in order:
		st.set_normal(n)
		st.add_vertex(p[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)

func _add_bar(parent: Node, a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var axis := b - a
	var ln := axis.length()
	if ln < 1e-5:
		return
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, ln)   # length lives on local Z
	m.mesh = bm
	m.material_override = mat
	m.position = (a + b) * 0.5
	# build an orthonormal basis with local Z along the bar; pick a helper axis
	# that is never parallel to the bar, so near-vertical pillars don't degenerate.
	var z := axis / ln
	var h := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := h.cross(z).normalized()
	var y := z.cross(x)
	m.basis = Basis(x, y, z)
	parent.add_child(m)

func set_cockpit_view(v: bool) -> void:
	# The greenhouse is now transparent glass, so it stays visible in every view;
	# only the driver-side steering wheel toggles with the cockpit camera.
	if _cockpit:
		_cockpit.visible = v

func _read_input(delta: float) -> void:
	# Pedals are analog and smoothed like a foot modulating them: W = accelerator, S = brake.
	var gas_in := 1.0 if (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) else 0.0
	var brk_in := 1.0 if (Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) else 0.0
	throttle = move_toward(throttle, gas_in, PEDAL_RATE * delta)
	brake = move_toward(brake, brk_in, PEDAL_RATE * delta)

	_longitudinal(delta)

	var steer_in := 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		steer_in += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		steer_in -= 1.0

	# Keyboard steering is momentary (returns to center); the on-screen wheel holds a set angle.
	var target := 0.0
	if absf(steer_in) > 0.001:
		target = deg_to_rad(max_steer_deg) * steer_in * steer_sign
	else:
		target = deg_to_rad(ui_steer_deg) * steer_sign
	var step := deg_to_rad(steer_rate_deg) * delta
	steer = move_toward(steer, target, step)

func _longitudinal(delta: float) -> void:
	# The brake always wins: it drives the speed to zero and holds there (no creep-through),
	# which is exactly how a 科目二 candidate modulates the clutch/brake to walk the car.
	if brake > 0.02:
		var stop := brake_decel * brake * delta
		if absf(speed) <= stop:
			speed = 0.0
		else:
			speed -= signf(speed) * stop
		return
	# P locks the car; N coasts to a stop; D/R turn the accelerator into motion in that direction.
	match gear:
		Gear.P:
			speed = move_toward(speed, 0.0, brake_decel * delta)
		Gear.N:
			speed = move_toward(speed, 0.0, coast_decel * delta)
		_:
			var dir := 1.0 if gear == Gear.D else -1.0
			var cap := max_speed if gear == Gear.D else max_reverse_speed
			var target := dir * (idle_creep_speed + throttle * (cap - idle_creep_speed))
			var rate := accel if throttle > 0.01 else coast_decel
			speed = move_toward(speed, target, rate * delta)

func set_gear(g: int) -> void:
	gear = clampi(g, Gear.P, Gear.D)

func gear_up() -> void:
	gear = clampi(gear + 1, Gear.P, Gear.D)

func gear_down() -> void:
	gear = clampi(gear - 1, Gear.P, Gear.D)

func _integrate(delta: float) -> void:
	var tan_d := tan(steer)
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	global_position += fwd * speed * delta

	if absf(tan_d) < 1e-4:
		turning_radius = INF
		for h in _front_hubs:
			h.rotation.y = 0.0
	else:
		turning_radius = wheel_base / tan_d
		# rotate about Y so the car follows the Ackermann circle
		rotate_y(-(speed / wheel_base) * tan_d * delta)
		_apply_ackermann_wheel_angles(turning_radius)

func _apply_ackermann_wheel_angles(r: float) -> void:
	# Each front wheel points along the tangent to its circle about the ICZ,
	# so inner and outer wheels converge on the ICZ (Ackermann). ICZ local pos = (r,0,0).
	# wheel at local x: steer angle gamma = atan(L / (r - x)); right turn = rotate_y negative.
	var hw := wheel_track * 0.5
	if _hub_fr:
		_hub_fr.rotation.y = -atan2(wheel_base, r - hw)
	if _hub_fl:
		_hub_fl.rotation.y = -atan2(wheel_base, r + hw)

func _spin_wheels(delta: float) -> void:
	var ang := (speed * delta) / 0.30
	for roll in _roll_nodes:
		roll.rotation.x += ang

# ---- queries used by the visualizer / HUD ----

func rear_center() -> Vector3:
	return global_position

func front_center() -> Vector3:
	return to_global(Vector3(0, 0.0, -wheel_base))

func fl_world() -> Vector3:
	return to_global(Vector3(-wheel_track * 0.5, 0.0, -wheel_base))

func fr_world() -> Vector3:
	return to_global(Vector3(wheel_track * 0.5, 0.0, -wheel_base))

func rl_world() -> Vector3:
	return to_global(Vector3(-wheel_track * 0.5, 0.0, 0.0))

func rr_world() -> Vector3:
	return to_global(Vector3(wheel_track * 0.5, 0.0, 0.0))

func wheel_positions() -> Dictionary:
	return {
		"fl": to_global(Vector3(-wheel_track * 0.5, 0.0, -wheel_base)),
		"fr": to_global(Vector3(wheel_track * 0.5, 0.0, -wheel_base)),
		"rl": to_global(Vector3(-wheel_track * 0.5, 0.0, 0.0)),
		"rr": to_global(Vector3(wheel_track * 0.5, 0.0, 0.0)),
	}

func icz() -> Vector3:
	if is_inf(turning_radius):
		return rear_center()
	var right := global_transform.basis.x
	return rear_center() + right * turning_radius

func min_turning_radius() -> float:
	# Outer front-wheel trace radius at full steering lock (the classic "minimum turning radius").
	var hw := wheel_track * 0.5
	var d := deg_to_rad(max_steer_deg)
	var r_center := wheel_base / tan(d)
	return sqrt(pow(r_center + hw, 2) + pow(wheel_base, 2))

func speed_kmh() -> float:
	return absf(speed) * 3.6

func steer_deg() -> float:
	return rad_to_deg(steer)
