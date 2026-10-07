extends Node3D
class_name ParkingCourse

# Builds 科目二 practice bays at standard proportions (see docs/科目二场地标准尺寸.md).
# Sizes are derived from the car's own dimensions via the GB/GA formulas, so the bay is
# always a "standard" bay for whatever vehicle is loaded.
#
#   倒车入库:  库长 = 车长 + 0.7 ; 库宽 = 车宽 + 0.6 ; 控制线距 = 1.5 × 车长
#   侧方停车:  车位长 = 1.5 × 车长 + 1 (小型车) ; 车位宽 = 车宽 + 0.8 ; 行车道宽 = 1.5 × 车宽 + 0.8

const COURSE_Y := 0.02

const EMPTY := 0
const REVERSE_IN := 1
const SIDE_PARK := 2

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var project := EMPTY
var _spawn_pos := Vector3.ZERO
var _spawn_yaw := 0.0

const C_LINE := Color(1.0, 0.85, 0.2)      # 库位/车道边线：黄色实线
const C_BAY := Color(0.25, 0.7, 1.0, 0.18)
const C_AISLE := Color(0.6, 0.66, 0.7, 0.08)
const C_CTRL := Color(1.0, 0.85, 0.2)      # 控制线：黄色虚线
const C_LANE := Color(0.8, 0.8, 0.8, 0.6)

func _build() -> void:
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_instance.material_override = mat
	add_child(_instance)

func spawn_position() -> Vector3:
	return _spawn_pos

func spawn_yaw() -> float:
	return _spawn_yaw

func set_project(kind: int, car_length: float, car_width: float) -> void:
	project = kind
	_mesh.clear_surfaces()
	_spawn_pos = Vector3.ZERO
	_spawn_yaw = 0.0
	if kind == REVERSE_IN:
		_build_reverse_in(car_length, car_width)
	elif kind == SIDE_PARK:
		_build_side_park(car_length, car_width)

# ---- 倒车入库 ----
# Layout matches the standard plan view (see docs): the bay hangs off the near road
# edge and opens into the road; the two CONTROL lines run PERPENDICULAR to the road
# edges at distance h out from each bay wall (not across the far edge).
func _build_reverse_in(cl: float, cw: float) -> void:
	var bay_w := cw + 0.6          # W 库宽 = 车宽 + 0.6
	var bay_l := cl + 0.7          # L 库长 = 车长 + 0.7
	var road_w := 1.5 * cl         # S 车道宽 = 1.5 × 车长
	var ctrl_h := cl               # h 控制线到库边线距离 (待标准确认，暂取 1×车长)
	var hw := bay_w * 0.5
	var span := hw + ctrl_h + 2.0  # how far the road/edge lines reach along X
	# bay floor (opens into the road at z=0) + road floor strip
	_fill_rect(Vector2(-hw, -bay_l), Vector2(hw, 0.0), C_BAY)
	_fill_rect(Vector2(-span, 0.0), Vector2(span, road_w), C_AISLE)
	# bay: back wall + two side walls (mouth at z=0 is left open)
	_seg(Vector3(-hw, 0, -bay_l), Vector3(hw, 0, -bay_l), C_LINE)   # 库底
	_seg(Vector3(-hw, 0, 0), Vector3(-hw, 0, -bay_l), C_LINE)       # 左库边线
	_seg(Vector3(hw, 0, 0), Vector3(hw, 0, -bay_l), C_LINE)         # 右库边线
	# road edges: near edge (z=0) drawn in two parts leaving the W-wide mouth open
	_seg(Vector3(-span, 0, 0), Vector3(-hw, 0, 0), C_LINE)
	_seg(Vector3(hw, 0, 0), Vector3(span, 0, 0), C_LINE)
	_seg(Vector3(-span, 0, road_w), Vector3(span, 0, road_w), C_LINE) # 远车道边线
	# control lines: yellow DASHED, perpendicular to the road edges, at x = ±(hw + h)
	_seg_dashed(Vector3(-(hw + ctrl_h), 0, 0), Vector3(-(hw + ctrl_h), 0, road_w), C_CTRL, 0.12)
	_seg_dashed(Vector3(hw + ctrl_h, 0, 0), Vector3(hw + ctrl_h, 0, road_w), C_CTRL, 0.12)
	# 库口前沿线：横跨库口的黄虚线（左右车道边线之间那一段）。
	_seg_dashed(Vector3(-hw, 0, 0), Vector3(hw, 0, 0), C_CTRL, 0.12)
	# spawn: at the right control line, mid-road, nose along +X (drive past, then reverse in)
	_spawn_pos = Vector3(hw + ctrl_h, 0, road_w * 0.5)
	_spawn_yaw = -PI * 0.5

# ---- 侧方停车 ----
func _build_side_park(cl: float, cw: float) -> void:
	var bay_l := 1.5 * cl + 1.0     # 车位长 (小型车, along X)
	var bay_w := cw + 0.8           # 车位宽 = 车宽 + 0.8 (along Z)
	var hl := bay_l * 0.5
	var lane_d := 1.5 * cw + 0.8    # 行车道宽 = 1.5×车宽 + 0.8, on the -Z side of the bay mouth
	# bay occupies x in [-hl,hl], z in [0,bay_w]; mouth is the open z=0 side facing the lane
	_fill_rect(Vector2(-hl, 0.0), Vector2(hl, bay_w), C_BAY)
	_seg(Vector3(-hl, 0, bay_w), Vector3(hl, 0, bay_w), C_LINE)   # back line
	_seg(Vector3(-hl, 0, 0), Vector3(-hl, 0, bay_w), C_LINE)      # left end
	_seg(Vector3(hl, 0, 0), Vector3(hl, 0, bay_w), C_LINE)        # right end
	# lane boundary lines running along X: inner (mouth) at z=0, outer at z=-lane_d
	_seg(Vector3(-hl - 8.0, 0, 0.0), Vector3(hl + 8.0, 0, 0.0), C_LANE, 0.05)
	_seg(Vector3(-hl - 8.0, 0, -lane_d), Vector3(hl + 8.0, 0, -lane_d), C_LANE, 0.05)
	# spawn on the lane just past the +X end, nose toward +X, so the student
	# drives forward then reverses (-X) into the bay (classic parallel park).
	_spawn_pos = Vector3(hl + cl * 0.5 + 1.0, 0.0, -lane_d * 0.5)
	_spawn_yaw = -PI * 0.5          # yaw -90deg turns the nose from -Z to +X

# ---- primitives ----
# Draw each marking as a thin ground ribbon (two triangles) so line thickness is a real
# width in metres — Godot's PRIMITIVE_LINES is stuck at 1px and reads as invisible.
func _seg(a: Vector3, b: Vector3, col: Color, w: float = 0.10) -> void:
	var dx := b.x - a.x
	var dz := b.z - a.z
	var ln := sqrt(dx * dx + dz * dz)
	if ln < 1e-5:
		return
	# unit normal (perpendicular in XZ), scaled to half the stripe width
	var ox := (dz / ln) * w * 0.5
	var oz := (-dx / ln) * w * 0.5
	var y := COURSE_Y
	var p0 := Vector3(a.x + ox, y, a.z + oz)
	var p1 := Vector3(a.x - ox, y, a.z - oz)
	var p2 := Vector3(b.x - ox, y, b.z - oz)
	var p3 := Vector3(b.x + ox, y, b.z + oz)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, null)
	_tri(p0, p1, p2, col)
	_tri(p0, p2, p3, col)
	_mesh.surface_end()

# A dashed ground stripe: walk a->b emitting short ribbons separated by gaps.
func _seg_dashed(a: Vector3, b: Vector3, col: Color, w: float = 0.12, dash := 0.45, gap := 0.35) -> void:
	var dx := b.x - a.x
	var dz := b.z - a.z
	var ln := sqrt(dx * dx + dz * dz)
	if ln < 1e-5:
		return
	var ux := dx / ln
	var uz := dz / ln
	var t := 0.0
	while t < ln:
		var t2 := minf(t + dash, ln)
		_seg(Vector3(a.x + ux * t, 0, a.z + uz * t), Vector3(a.x + ux * t2, 0, a.z + uz * t2), col, w)
		t = t2 + gap

func _fill_rect(min_xz: Vector2, max_xz: Vector2, col: Color) -> void:
	var y := COURSE_Y - 0.002
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, null)
	_tri(Vector3(min_xz.x, y, min_xz.y), Vector3(min_xz.x, y, max_xz.y), Vector3(max_xz.x, y, max_xz.y), col)
	_tri(Vector3(min_xz.x, y, min_xz.y), Vector3(max_xz.x, y, max_xz.y), Vector3(max_xz.x, y, min_xz.y), col)
	_mesh.surface_end()

func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(c)
