extends Node3D

const MIRROR_SHADER := preload("res://shaders/mirror.gdshader")
const GEAR_LABELS := ["P", "R", "N", "D"]
const GRID_STEP := 5.0   # metres between grid lines (raise to make the grid sparser)

var car: AckermannCar
var traj: TurnViz
var course: ParkingCourse
var _rig: MirrorRig

var _cam: Camera3D
var _view_mode := 0   # 0=chase(perspective) 1=top(ortho) 2=side(ortho)
var _chase_pos := Vector3.ZERO

var _hud: Label
var _dbg: Label
var _wheel: SteeringWheel
var _pedals: PedalPanel
var _gear_btns: Array[Button] = []
var _ground: MeshInstance3D
var _grid: MeshInstance3D
var _show_circles := false
var _car_reset_pos := Vector3.ZERO
var _car_reset_yaw := 0.0
var _project := ParkingCourse.REVERSE_IN
var _c_held := false
var _r_held := false
var _sp_held := false
var _dbg_held := false
var _p1_held := false
var _p2_held := false
var _p3_held := false
var _q_held := false
var _e_held := false
var _v_held := false

# driver-seat adjustment (metres), applied in the cockpit camera's local frame
var _seat_fore_aft := 0.0     # + = toward the nose
var _seat_height := 0.0       # + = higher
var _seat_panel: Control
var _fa_slider: HSlider
var _ht_slider: HSlider
const SEAT_FA_RANGE := 0.6
const SEAT_H_UP := 0.5
const SEAT_H_DN := 0.3

func _ready() -> void:
	# the root must stay identity: everything (ground/grid/car/camera) inherits it.
	transform = Transform3D()
	_setup_input()
	_build_world()
	_build_car()
	_build_course()
	_build_cameras()
	_build_hud()

func _setup_input() -> void:
	_add_key("throttle", [KEY_W, KEY_UP])
	_add_key("brake", [KEY_S, KEY_DOWN])
	_add_key("steer_left", [KEY_A, KEY_LEFT])
	_add_key("steer_right", [KEY_D, KEY_RIGHT])
	_add_key("toggle_view", [KEY_C])
	_add_key("reset", [KEY_R])
	_add_key("clear_track", [KEY_SPACE])

func _add_key(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
		var e2 := InputEventKey.new()
		e2.keycode = k
		InputMap.action_add_event(action, e2)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.55, 0.68, 0.8)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.6, 0.6, 0.65)
	we.ambient_light_energy = 0.6
	env.environment = we
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1500, 1500)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.32, 0.34, 0.36)
	ground.material_override = gmat
	add_child(ground)
	_ground = ground

	_build_grid()

func _build_grid() -> void:
	# grid for judging turning radius visually; GRID_STEP = metres between lines
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)
	_grid = mi
	im.surface_begin(Mesh.PRIMITIVE_LINES, null)
	var half := 100.0
	var col := Color(0.5, 0.5, 0.5, 0.4)
	var i := -half
	while i <= half:
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(i, 0.008, -half))
		im.surface_add_vertex(Vector3(i, 0.008, half))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(-half, 0.008, i))
		im.surface_add_vertex(Vector3(half, 0.008, i))
		i += GRID_STEP
	im.surface_end()

func _build_car() -> void:
	car = AckermannCar.new()
	add_child(car)
	car._build()

	traj = TurnViz.new()
	car.add_child(traj)
	traj._build()

	_rig = MirrorRig.new()
	car.add_child(_rig)
	_rig._build(car)

func _build_course() -> void:
	# course lives at the world origin, NOT parented to the car
	course = ParkingCourse.new()
	add_child(course)
	course._build()
	_set_project(_project)

func _build_cameras() -> void:
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 500.0
	add_child(_cam)
	# start behind the car (relative to its spawn yaw) so the first frame is sane
	var fwd := Vector3(-sin(_car_reset_yaw), 0.0, -cos(_car_reset_yaw))
	_chase_pos = _car_reset_pos - fwd * 6.5 + Vector3(0, 3.2, 0)
	_cam.global_position = _chase_pos
	_cam.look_at(_car_reset_pos + Vector3(0, 1.0, 0), Vector3.UP)
	_cam.make_current()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# MODE info: anchored to the left edge, vertically centered
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_hud.grow_horizontal = Control.GROW_DIRECTION_END
	_hud.grow_vertical = Control.GROW_DIRECTION_BOTH   # stay centered on the mid line
	_hud.offset_left = 16
	_hud.add_theme_font_size_override("font_size", 18)
	layer.add_child(_hud)

	# debug info: anchored to the bottom-left corner
	_dbg = Label.new()
	_dbg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_dbg.grow_horizontal = Control.GROW_DIRECTION_END
	_dbg.grow_vertical = Control.GROW_DIRECTION_BEGIN   # expand upward from the bottom
	_dbg.offset_left = 16
	_dbg.offset_bottom = -12
	_dbg.add_theme_font_size_override("font_size", 14)
	_dbg.add_theme_color_override("font_color", Color(1, 1, 0.4))
	layer.add_child(_dbg)

	# controls tucked into a single drop-down menu on the right edge (was a column of 7 buttons)
	var menu := MenuButton.new()
	menu.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # right edge sticks to the side
	menu.grow_vertical = Control.GROW_DIRECTION_BOTH      # center vertically on the mid line
	menu.offset_right = -12
	menu.offset_top = -18
	menu.offset_bottom = 18
	menu.text = "菜单 Menu"
	layer.add_child(menu)
	var popup := menu.get_popup()
	popup.add_item("切换视角 Toggle View (C)", 0)
	popup.add_item("驾驶位 Cockpit (V)", 1)
	popup.add_item("复位 Reset (R)", 2)
	popup.add_item("显示完整转弯圆 Show Circle (Space)", 3)
	popup.add_separator()
	popup.add_item("空场 Open (1)", 4)
	popup.add_item("倒车入库 Reverse (2)", 5)
	popup.add_item("侧方停车 Parallel (3)", 6)
	popup.id_pressed.connect(_on_menu_action)

	# on-screen steering wheel, bottom-left, sets & holds the front-wheel angle
	_wheel = SteeringWheel.new()
	_wheel.custom_minimum_size = Vector2(170, 170)
	_wheel.max_front_deg = car.max_steer_deg
	_wheel.anchor_left = 0.0
	_wheel.anchor_right = 0.0
	_wheel.anchor_top = 1.0
	_wheel.anchor_bottom = 1.0
	_wheel.offset_left = 24
	_wheel.offset_top = -194
	_wheel.offset_right = 194
	_wheel.offset_bottom = -24
	layer.add_child(_wheel)
	_wheel.steer_changed.connect(_on_wheel_steer)

	var wb := Button.new()
	wb.text = "Steer Center"
	wb.anchor_left = 0.0
	wb.anchor_right = 0.0
	wb.anchor_top = 1.0
	wb.anchor_bottom = 1.0
	wb.offset_left = 210
	wb.offset_top = -70
	wb.offset_right = 400
	wb.offset_bottom = -40
	wb.pressed.connect(func(): _wheel.center())
	layer.add_child(wb)

	# pedals + gear, bottom-right
	_pedals = PedalPanel.new()
	_pedals.custom_minimum_size = Vector2(150, 190)
	_pedals.anchor_left = 1.0
	_pedals.anchor_right = 1.0
	_pedals.anchor_top = 1.0
	_pedals.anchor_bottom = 1.0
	_pedals.offset_left = -174
	_pedals.offset_top = -200
	_pedals.offset_right = -24
	_pedals.offset_bottom = -24
	layer.add_child(_pedals)

	_build_shifter(layer)
	_build_mirror_hud(layer)
	_build_seat_panel(layer)

func _build_shifter(layer: CanvasLayer) -> void:
	# automatic-style P/R/N/D selector, left of the pedals
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -266
	box.offset_right = -186
	box.offset_top = -200
	box.offset_bottom = -24
	box.add_theme_constant_override("separation", 4)
	layer.add_child(box)

	var cap := Label.new()
	cap.text = "挡位 Q/E"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 12)
	box.add_child(cap)

	_gear_btns.clear()
	for g in [AckermannCar.Gear.P, AckermannCar.Gear.R, AckermannCar.Gear.N, AckermannCar.Gear.D]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(_select_gear.bind(g))
		box.add_child(b)
		_gear_btns.append(b)
	_refresh_shifter()

func _select_gear(g: int) -> void:
	car.set_gear(g)
	_refresh_shifter()

func _refresh_shifter() -> void:
	for i in _gear_btns.size():
		var active := car.gear == i
		_gear_btns[i].text = GEAR_LABELS[i]
		_gear_btns[i].modulate = Color(1, 0.85, 0.3) if active else Color(0.7, 0.7, 0.7)

func _build_seat_panel(layer: CanvasLayer) -> void:
	# seat-adjust UI, shown only in the cockpit view (visibility toggled in _update_cameras)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -170
	panel.offset_right = 170
	panel.offset_top = -104
	panel.offset_bottom = -16
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	_seat_panel = panel
	panel.visible = false

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var cap := Label.new()
	cap.text = "座椅调节  I/K 上下 · J/L 前后"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 12)
	v.add_child(cap)

	v.add_child(_mk_slider_row("前后", -SEAT_FA_RANGE, SEAT_FA_RANGE, _seat_fore_aft, _on_seat_fore_aft, true))
	v.add_child(_mk_slider_row("上下", -SEAT_H_DN, SEAT_H_UP, _seat_height, _on_seat_height, false))

func _mk_slider_row(title: String, mn: float, mx: float, val: float, cb: Callable, is_fa: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = title
	lbl.custom_minimum_size = Vector2(34, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 0.01
	s.custom_minimum_size = Vector2(240, 18)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if is_fa:
		_fa_slider = s
	else:
		_ht_slider = s
	s.value = val
	s.value_changed.connect(cb)
	row.add_child(s)
	return row

func _build_mirror_hud(layer: CanvasLayer) -> void:
	var box := HBoxContainer.new()
	# span the full top edge and center the row so the enlarged side mirrors fit
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.offset_left = 0.0
	box.offset_right = 0.0
	box.offset_top = 6
	box.offset_bottom = 290
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	_add_mirror_panel(box, MirrorRig.LEFT, 1.2)
	_add_mirror_panel(box, MirrorRig.CENTER, 0.8)
	_add_mirror_panel(box, MirrorRig.RIGHT, 1.2)

func _add_mirror_panel(parent: Control, idx: int, scale: float) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	parent.add_child(v)

	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(292.0 * scale, 184.0 * scale)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture = _rig.texture(idx)
	var mat := ShaderMaterial.new()
	mat.shader = MIRROR_SHADER
	mat.set_shader_parameter("mirror_tex", _rig.texture(idx))
	mat.set_shader_parameter("convex", _rig.is_convex(idx))
	mat.set_shader_parameter("curvature", 0.30 if _rig.is_convex(idx) else 0.0)
	rect.material = mat

	# black frame so the mirror boundary is visible even where the convex shader
	# masks the warped-out corners to transparent
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 1)
	sb.border_color = Color(0, 0, 0, 1)
	sb.set_border_width_all(4)
	sb.set_content_margin_all(4.0)
	frame.add_theme_stylebox_override("panel", sb)
	frame.add_child(rect)
	v.add_child(frame)

	# aiming controls (only for the two adjustable convex side mirrors)
	var adj := HBoxContainer.new()
	adj.add_theme_constant_override("separation", 2)
	v.add_child(adj)
	if _rig.is_convex(idx):
		_adj_button(adj, "◀", func(): _rig.adjust_yaw(idx, -0.06))
		_adj_button(adj, "▶", func(): _rig.adjust_yaw(idx, 0.06))
		_adj_button(adj, "▲", func(): _rig.adjust_pitch(idx, 0.05))
		_adj_button(adj, "▼", func(): _rig.adjust_pitch(idx, -0.05))

func _adj_button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(34, 22)
	b.pressed.connect(cb)
	parent.add_child(b)

func _on_wheel_steer(deg: float) -> void:
	car.ui_steer_deg = deg

func _on_menu_action(id: int) -> void:
	match id:
		0:
			_toggle_view()
		1:
			_go_cockpit()
		2:
			_reset_car()
		3:
			_toggle_circles()
		4:
			_proj_open()
		5:
			_proj_reverse()
		6:
			_proj_side()

func _physics_process(delta: float) -> void:
	car.tick(delta)
	traj.update(car)
	_rig._sync(car)
	if _view_mode == 3:
		_adjust_seat(delta)
	_update_cameras(delta)
	_sync_wheel_display()
	_sync_pedals()
	_update_hud()
	_update_debug()

	# global hotkeys (direct polling, reliable)
	if Input.is_physical_key_pressed(KEY_C) and not _c_held:
		_toggle_view()
	_c_held = Input.is_physical_key_pressed(KEY_C)
	if Input.is_physical_key_pressed(KEY_V) and not _v_held:
		_go_cockpit()
	_v_held = Input.is_physical_key_pressed(KEY_V)
	if Input.is_physical_key_pressed(KEY_R) and not _r_held:
		_reset_car()
	_r_held = Input.is_physical_key_pressed(KEY_R)
	if Input.is_physical_key_pressed(KEY_SPACE) and not _sp_held:
		_toggle_circles()
	_sp_held = Input.is_physical_key_pressed(KEY_SPACE)
	if Input.is_physical_key_pressed(KEY_F1) and not _dbg_held:
		_dbg.visible = not _dbg.visible
	_dbg_held = Input.is_physical_key_pressed(KEY_F1)
	if Input.is_physical_key_pressed(KEY_1) and not _p1_held:
		_proj_open()
	_p1_held = Input.is_physical_key_pressed(KEY_1)
	if Input.is_physical_key_pressed(KEY_2) and not _p2_held:
		_proj_reverse()
	_p2_held = Input.is_physical_key_pressed(KEY_2)
	if Input.is_physical_key_pressed(KEY_3) and not _p3_held:
		_proj_side()
	_p3_held = Input.is_physical_key_pressed(KEY_3)
	if Input.is_physical_key_pressed(KEY_Q) and not _q_held:
		car.gear_down()
		_refresh_shifter()
	_q_held = Input.is_physical_key_pressed(KEY_Q)
	if Input.is_physical_key_pressed(KEY_E) and not _e_held:
		car.gear_up()
		_refresh_shifter()
	_e_held = Input.is_physical_key_pressed(KEY_E)

func _update_cameras(delta: float) -> void:
	car.set_cockpit_view(_view_mode == 3)
	if _seat_panel:
		_seat_panel.visible = (_view_mode == 3)
	var rear := car.rear_center()
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	_cam.top_level = true
	if _view_mode == 1:
		# true orthographic plan view: straight down, screen-up = world -Z
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.global_position = Vector3(rear.x, 60, rear.z)
		_cam.look_at(Vector3(rear.x, 0.0, rear.z), Vector3(0, 0, -1))
		if _show_circles and not is_inf(car.turning_radius):
			_cam.size = clampf(2.0 * absf(car.turning_radius) + 8.0, 16.0, 160.0)
		elif _project != ParkingCourse.EMPTY:
			_cam.size = 30.0
		else:
			_cam.size = 20.0
	elif _view_mode == 2:
		# true orthographic side elevation: look along -X, screen-up = world +Y.
		# ground line is horizontal -> tire-to-ground contact is unambiguous.
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.global_position = Vector3(rear.x + 60, 0.8, rear.z)
		_cam.look_at(Vector3(rear.x, 0.8, rear.z), Vector3.UP)
		_cam.size = 6.0
	elif _view_mode == 3:
		# driver-seat first person: camera at the seat (left side, LHD), looking forward.
		# seat fore/aft + height come from the adjustment offsets (local frame, forward = -Z).
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		var gt := car.global_transform
		var lx := -car.track_width * 0.25
		var ly := 1.15 + _seat_height
		var lz := -car.wheel_base * 0.55 - _seat_fore_aft
		var seat := gt * Vector3(lx, ly, lz)
		var look := gt * Vector3(lx, ly - 0.2, lz - 6.0)
		_cam.global_position = seat
		_cam.look_at(look, gt.basis.y)
	else:
		# chase view from above-behind
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		var desired := rear - fwd * 6.5 + Vector3(0, 3.2, 0)
		_chase_pos = _chase_pos.lerp(desired, clampf(delta * 6.0, 0.0, 1.0))
		_cam.global_position = _chase_pos
		_cam.look_at(rear + Vector3(0, 1.0, 0), Vector3.UP)

	# keep ground + grid centered under the car so it looks infinite.
	# ground snaps to 1 m; grid snaps to GRID_STEP so its lines stay on the world grid.
	var snap := Vector3(roundf(rear.x), 0.0, roundf(rear.z))
	_ground.position = snap
	_grid.position = Vector3(
		roundf(rear.x / GRID_STEP) * GRID_STEP,
		0.0,
		roundf(rear.z / GRID_STEP) * GRID_STEP)

func _sync_wheel_display() -> void:
	if _wheel and not _wheel.dragging:
		_wheel.set_angle(car.steer_deg())

func _sync_pedals() -> void:
	if not _pedals:
		return
	if _pedals.throttle != car.throttle or _pedals.brake != car.brake or _pedals.gear != car.gear:
		_pedals.throttle = car.throttle
		_pedals.brake = car.brake
		_pedals.gear = car.gear
		_pedals.queue_redraw()

func _update_hud() -> void:
	var r_txt := "∞" if is_inf(car.turning_radius) else "%.2f m" % absf(car.turning_radius)
	var min_r := car.min_turning_radius()
	var dbg := "GEAR=%s  GAS=%d%%  BRAKE=%d%%" % [
		GEAR_LABELS[clampi(car.gear, 0, 3)],
		int(roundf(car.throttle * 100.0)), int(roundf(car.brake * 100.0))
	]
	var mode := "CHASE (perspective)"
	if _view_mode == 1:
		mode = "TOP (ortho)"
	elif _view_mode == 2:
		mode = "SIDE (ortho)"
	elif _view_mode == 3:
		mode = "COCKPIT (driver)"
	var proj := "空场 Open"
	if _project == ParkingCourse.REVERSE_IN:
		proj = "倒车入库 Reverse"
	elif _project == ParkingCourse.SIDE_PARK:
		proj = "侧方停车 Parallel"
	_hud.text = "MODE: %s\nCOURSE: %s\nSpeed: %.1f km/h\nSteer: %.1f deg\nTurning radius R: %s\nMin R (full lock): %.2f m\n%s\n[Q/E] gear  [F1] debug  [1/2/3] course" % [
		mode, proj, car.speed_kmh(), car.steer_deg(), r_txt, min_r, dbg
	]

func _fmt(v: Vector3) -> String:
	return "(%6.2f, %6.2f, %6.2f)" % [v.x, v.y, v.z]

func _update_debug() -> void:
	if not _dbg.visible:
		return
	var cb := car.global_transform.basis
	var cam_fwd := -_cam.global_transform.basis.z
	var cam_up := _cam.global_transform.basis.y
	var gb := _grid.global_transform.basis
	var proj := "PERSP" if _cam.projection == Camera3D.PROJECTION_PERSPECTIVE else "ORTHO"
	_dbg.text = "── DEBUG (mode=%d) ──\n" % _view_mode + \
		"CAR pos  %s\n" % _fmt(car.global_position) + \
		"CAR fwd  %s   up %s\n" % [_fmt(-cb.z), _fmt(cb.y)] + \
		"CAR yaw  %.1f deg\n" % rad_to_deg(atan2(-cb.z.x, -cb.z.z)) + \
		"CAM pos  %s\n" % _fmt(_cam.global_position) + \
		"CAM view %s   up %s\n" % [_fmt(cam_fwd), _fmt(cam_up)] + \
		"CAM %s  size=%.1f fov=%.0f\n" % [proj, _cam.size, _cam.fov] + \
		"GRID pos %s\n" % _fmt(_grid.global_position) + \
		"GRID x %s  y %s  z %s\n" % [_fmt(gb.x), _fmt(gb.y), _fmt(gb.z)] + \
		"GROUND pos %s\n" % _fmt(_ground.global_position)

func _toggle_view() -> void:
	_view_mode = (_view_mode + 1) % 4

func _go_cockpit() -> void:
	_view_mode = 3

func _adjust_seat(delta: float) -> void:
	# keyboard nudge (only in cockpit); I/K raise-lower, J/L move back-forward.
	var rate := 0.8 * delta
	if Input.is_physical_key_pressed(KEY_I):
		_seat_height = clampf(_seat_height + rate, -SEAT_H_DN, SEAT_H_UP)
	if Input.is_physical_key_pressed(KEY_K):
		_seat_height = clampf(_seat_height - rate, -SEAT_H_DN, SEAT_H_UP)
	if Input.is_physical_key_pressed(KEY_L):
		_seat_fore_aft = clampf(_seat_fore_aft + rate, -SEAT_FA_RANGE, SEAT_FA_RANGE)
	if Input.is_physical_key_pressed(KEY_J):
		_seat_fore_aft = clampf(_seat_fore_aft - rate, -SEAT_FA_RANGE, SEAT_FA_RANGE)
	_sync_seat_sliders()

func _on_seat_fore_aft(v: float) -> void:
	_seat_fore_aft = v

func _on_seat_height(v: float) -> void:
	_seat_height = v

func _sync_seat_sliders() -> void:
	if _fa_slider and absf(_fa_slider.value - _seat_fore_aft) > 1e-4:
		_fa_slider.value = _seat_fore_aft
	if _ht_slider and absf(_ht_slider.value - _seat_height) > 1e-4:
		_ht_slider.value = _seat_height

func _reset_car() -> void:
	car.global_position = _car_reset_pos
	car.global_transform.basis = Basis(Vector3.UP, _car_reset_yaw)
	car.speed = 0.0
	car.steer = 0.0
	car.ui_steer_deg = 0.0
	car.turning_radius = INF
	car.throttle = 0.0
	car.brake = 0.0
	car.set_gear(AckermannCar.Gear.D)
	# snap the chase camera behind the spawn so a project switch doesn't glide across the map
	var fwd := Vector3(-sin(_car_reset_yaw), 0.0, -cos(_car_reset_yaw))
	_chase_pos = _car_reset_pos - fwd * 6.5 + Vector3(0, 3.2, 0)
	if _cam:
		_cam.global_position = _chase_pos
		_cam.look_at(_car_reset_pos + Vector3(0, 1.0, 0), Vector3.UP)
	if _wheel:
		_wheel.center()
	_seat_fore_aft = 0.0
	_seat_height = 0.0
	_sync_seat_sliders()
	_refresh_shifter()

func _set_project(kind: int) -> void:
	_project = kind
	course.set_project(kind, car.overall_length, car.track_width)
	_car_reset_pos = course.spawn_position()
	_car_reset_yaw = course.spawn_yaw()
	_reset_car()

func _toggle_circles() -> void:
	_show_circles = not _show_circles
	traj.set_show_circles(_show_circles)

func _proj_open() -> void:
	_set_project(ParkingCourse.EMPTY)

func _proj_reverse() -> void:
	_set_project(ParkingCourse.REVERSE_IN)

func _proj_side() -> void:
	_set_project(ParkingCourse.SIDE_PARK)
