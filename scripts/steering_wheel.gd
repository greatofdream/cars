extends Control
class_name SteeringWheel

# Draggable on-screen steering wheel. Drag to set & HOLD a front-wheel angle.
# Emits steer_changed(front_deg) where + = right.

signal steer_changed(front_deg: float)

@export var max_front_deg: float = 34.0
@export var visual_ratio: float = 4.0   # wheel spins this many turns per unit of front angle (feels like a real wheel)

var front_steer_deg: float = 0.0
var dragging := false
var _last_angle := 0.0
var _radius := 70.0

func _ready() -> void:
	custom_minimum_size = Vector2(160, 160)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _center() -> Vector2:
	return size * 0.5

func _pointer_angle(p: Vector2) -> float:
	var c := _center()
	return atan2(p.y - c.y, p.x - c.x)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.position.distance_to(_center()) <= size.y * 0.5:
					dragging = true
					_last_angle = _pointer_angle(mb.position)
			else:
				dragging = false
			accept_event()
	elif event is InputEventMouseMotion:
		if dragging:
			var mm := event as InputEventMouseMotion
			var a := _pointer_angle(mm.position)
			var d := a - _last_angle
			while d > PI:
				d -= TAU
			while d < -PI:
				d += TAU
			# screen y is down, so dragging clockwise (right turn) increases the angle
			front_steer_deg = clampf(front_steer_deg + rad_to_deg(d) / visual_ratio, -max_front_deg, max_front_deg)
			_last_angle = a
			steer_changed.emit(front_steer_deg)
			queue_redraw()

func set_angle(deg: float) -> void:
	# external sync (e.g. when keyboard drives the car)
	if dragging:
		return
	front_steer_deg = clampf(deg, -max_front_deg, max_front_deg)
	queue_redraw()

func center() -> void:
	front_steer_deg = 0.0
	steer_changed.emit(0.0)
	queue_redraw()

func _draw() -> void:
	var c := _center()
	var r := minf(size.x, size.y) * 0.5 - 8.0
	_radius = r
	var rot := deg_to_rad(front_steer_deg) * visual_ratio

	# base plate
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.13, 0.16, 0.55))
	# rim
	draw_arc(c, r, 0, TAU, 64, Color(0.85, 0.86, 0.9), 12.0, true)
	# spokes (rotate with the wheel)
	for i in range(3):
		var a := rot - PI / 2.0 + i * TAU / 3.0
		draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(0.6, 0.62, 0.68), 8.0)
	# hub
	draw_circle(c, r * 0.18, Color(0.2, 0.25, 0.35))
	# top marker so rotation is visible
	var tm := rot - PI / 2.0
	draw_circle(c + Vector2(cos(tm), sin(tm)) * r, 11.0, Color(1.0, 0.35, 0.35))
	# angle text
	draw_string(ThemeDB.fallback_font, Vector2(0, size.y - 8), "%.0f°" % front_steer_deg,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(0.95, 0.95, 0.95))
