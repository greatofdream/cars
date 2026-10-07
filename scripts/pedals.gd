extends Control
class_name PedalPanel

# Draws the accelerator + brake pedals and the gear selector, filling each pedal
# from the bottom by its 0..1 travel so foot pressure is readable next to the wheel.

var throttle := 0.0
var brake := 0.0
var gear := 3   # 0=P 1=R 2=N 3=D (matches AckermannCar.Gear)
const GEAR_NAMES := ["P 驻车", "R 倒车", "N 空挡", "D 前进"]

const C_GAS := Color(0.35, 0.85, 0.4)
const C_BRAKE := Color(0.9, 0.25, 0.22)
const C_TRACK := Color(1, 1, 1, 0.12)
const C_TEXT := Color(1, 1, 1, 0.92)

func _draw() -> void:
	var w := size.x
	var h := size.y
	var pad := 6.0
	var pedal_w := (w - pad * 3.0) * 0.5
	var body_h := h - 34.0

	# brake (left)
	var bx := pad
	_pedal(bx, 24.0, pedal_w, body_h, brake, C_BRAKE, "刹车", "S")
	# accelerator (right)
	var gx := pad * 2.0 + pedal_w
	_pedal(gx, 24.0, pedal_w, body_h, throttle, C_GAS, "油门", "W")

	var label: String = GEAR_NAMES[clampi(gear, 0, 3)]
	draw_string(ThemeDB.fallback_font, Vector2(pad, 16.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, w - 2.0 * pad, 15, Color(1, 0.9, 0.4))

func _pedal(x: float, y: float, pw: float, ph: float, v: float, col: Color, name: String, key: String) -> void:
	var rect := Rect2(x, y, pw, ph)
	draw_rect(rect, C_TRACK, true)
	var fill_h := ph * clampf(v, 0.0, 1.0)
	draw_rect(Rect2(x, y + ph - fill_h, pw, fill_h), col, true)
	draw_rect(rect, col.lightened(0.25), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(x, y + ph + 14.0), "%s [%s]" % [name, key],
		HORIZONTAL_ALIGNMENT_CENTER, pw, 12, C_TEXT)
