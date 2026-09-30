# docking_station.gd
# Orbital docking station for the victory sequence (spawned by main_level.gd
# when the boss is defeated).
#
# play_docking(ship) runs the whole choreography with node-bound tweens (so it
# freezes with the tree and dies with the level):
#   1. wait start_delay (the boss death sequence)
#   2. descend from start_y to dock_y over descend_time (ease out)
#   3. emit ready_for_ship; the level flies the ship to get_dock_position()
#      (player.fly_to(pos, ship_fly_time)); the station waits for the ship's
#      `arrived` signal (or ship_fly_time if the ship has none)
#   4. close the clamps over clamp_time (emits clamps_closed at the end)
#   5. white flash over the port (flash_time) + "DOCKED" label pop
#   6. wait finish_delay, emit docking_finished
#
# PLACEHOLDER_ART: the station is built from Polygon2D primitives in
# _build_placeholder_art(). To swap: add a Sprite2D "Hull" (~800x600 PNG,
# port at bottom center) to docking_station.tscn, delete the primitive code,
# and turn ClampLeft / ClampRight into sprites (or an AnimatedSprite2D clamp
# sheet driven from _close_clamps()). Keep DockPoint at the port's
# center-bottom.
extends Node2D

signal ready_for_ship
signal clamps_closed
signal docking_finished

@export_group("Timeline")
## Wait before the station appears (boss death sequence, ~1.5 s)
@export var start_delay: float = 1.5
@export var descend_time: float = 2.0
## Duration the level passes to player.fly_to()
@export var ship_fly_time: float = 2.0
@export var clamp_time: float = 0.6
@export var flash_time: float = 0.2
## Wait after the DOCKED pop before docking_finished
@export var finish_delay: float = 1.0

@export_group("Placement")
@export var start_y: float = -300.0
@export var dock_y: float = 260.0
## Open clamp angle (degrees; left arm +angle, right arm -angle)
@export var clamp_open_degrees: float = 35.0
@export var nav_blink_interval: float = 0.5

const DOCKED_FONT := preload("res://fonts/m5x7.ttf")
const DOCKED_COLOR := Color(1, 0.8, 0.2)

# Placeholder geometry (station-local px)
const HULL_SIZE := Vector2(520, 180)
const PORT_SIZE := Vector2(120, 60)
const PANEL_SIZE := Vector2(90, 130)
const CLAMP_LENGTH := 80.0

@onready var dock_point: Marker2D = $DockPoint
@onready var nav_timer: Timer = $NavTimer

var clamp_left: Polygon2D
var clamp_right: Polygon2D
var flash: Polygon2D
var docked_label: Label
var nav_light_red: Polygon2D
var nav_light_green: Polygon2D

var _ship: Node2D = null
var _tween: Tween
var _docking: bool = false
var _ship_arrived: bool = false

func _ready() -> void:
	_build_placeholder_art()
	_set_clamps_open(true)
	nav_timer.wait_time = nav_blink_interval
	nav_timer.timeout.connect(_on_nav_blink)
	nav_timer.start()

## Station-global position the ship's origin should fly to
func get_dock_position() -> Vector2:
	return dock_point.global_position

func play_docking(ship: Node2D) -> void:
	if _docking:
		return
	_docking = true
	_ship = ship
	_ship_arrived = false
	position.y = start_y
	_set_clamps_open(true)
	if is_instance_valid(ship) and ship.has_signal("arrived"):
		ship.connect("arrived", _on_ship_arrived, CONNECT_ONE_SHOT)

	_tween = create_tween()
	_tween.tween_interval(start_delay)
	_tween.tween_property(self, "position:y", dock_y, descend_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_on_descended)

func _on_descended() -> void:
	ready_for_ship.emit()
	# Ship without an `arrived` signal: assume it takes ship_fly_time
	if not (is_instance_valid(_ship) and _ship.has_signal("arrived")):
		_tween = create_tween()
		_tween.tween_interval(ship_fly_time)
		_tween.tween_callback(_on_ship_arrived)

func _on_ship_arrived() -> void:
	if _ship_arrived or not _docking:
		return
	_ship_arrived = true
	_close_clamps()

func _close_clamps() -> void:
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(clamp_left, "rotation", 0.0, clamp_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_property(clamp_right, "rotation", 0.0, clamp_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(_on_clamps_closed)

func _on_clamps_closed() -> void:
	clamps_closed.emit()

	# Flash over the port, DOCKED pops under the ship
	flash.visible = true
	flash.modulate.a = 0.0
	docked_label.visible = true
	docked_label.scale = Vector2.ZERO
	_tween = create_tween()
	_tween.tween_property(flash, "modulate:a", 1.0, flash_time * 0.5)
	_tween.tween_property(flash, "modulate:a", 0.0, flash_time * 0.5)
	_tween.parallel().tween_property(docked_label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(finish_delay)
	_tween.tween_callback(_on_finished)

func _on_finished() -> void:
	flash.visible = false
	docking_finished.emit()

func _set_clamps_open(open: bool) -> void:
	var angle := deg_to_rad(clamp_open_degrees) if open else 0.0
	clamp_left.rotation = angle
	clamp_right.rotation = -angle

func _on_nav_blink() -> void:
	nav_light_red.visible = not nav_light_red.visible
	nav_light_green.visible = not nav_light_red.visible

# --- Placeholder art -------------------------------------------------------

func _rect(size: Vector2, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var h := size / 2.0
	return PackedVector2Array([
		center + Vector2(-h.x, -h.y), center + Vector2(h.x, -h.y),
		center + Vector2(h.x, h.y), center + Vector2(-h.x, h.y)])

func _poly(node_name: String, points: PackedVector2Array, color: Color, parent: Node = self) -> Polygon2D:
	var p := Polygon2D.new()
	p.name = node_name
	p.polygon = points
	p.color = color
	parent.add_child(p)
	return p

func _build_placeholder_art() -> void:
	var half_hull := HULL_SIZE / 2.0
	var port_top := half_hull.y - PORT_SIZE.y  # Port is flush with the hull bottom

	# PLACEHOLDER_ART: solar panels (dark blue with lighter stripes), one per side
	for side in [-1.0, 1.0]:
		var panel_center := Vector2(side * (half_hull.x + PANEL_SIZE.x / 2.0), -10.0)
		var strut := _poly("Strut", _rect(Vector2(24, 10), Vector2(side * (half_hull.x + 6.0), -10.0)),
			Color(0.45, 0.48, 0.55))
		strut.z_index = -1
		var panel := _poly("SolarPanelLeft" if side < 0.0 else "SolarPanelRight",
			_rect(PANEL_SIZE, panel_center), Color(0.08, 0.14, 0.4))
		panel.z_index = -1
		for i in range(1, 5):
			var y := -PANEL_SIZE.y / 2.0 + PANEL_SIZE.y * float(i) / 5.0
			_poly("Stripe%d" % i, _rect(Vector2(PANEL_SIZE.x - 8.0, 4.0), Vector2(0.0, y)),
				Color(0.3, 0.45, 0.85), panel).position = panel_center

	# PLACEHOLDER_ART: hull (grey-blue, bevelled corners) with a lighter band
	_poly("Hull", PackedVector2Array([
		Vector2(-half_hull.x + 30, -half_hull.y), Vector2(half_hull.x - 30, -half_hull.y),
		Vector2(half_hull.x, -half_hull.y + 30), Vector2(half_hull.x, half_hull.y - 30),
		Vector2(half_hull.x - 30, half_hull.y), Vector2(-half_hull.x + 30, half_hull.y),
		Vector2(-half_hull.x, half_hull.y - 30), Vector2(-half_hull.x, -half_hull.y + 30),
	]), Color(0.46, 0.53, 0.63))
	_poly("HullBand", _rect(Vector2(HULL_SIZE.x - 40.0, 26.0), Vector2(0, -30)), Color(0.6, 0.67, 0.76))

	# PLACEHOLDER_ART: docking port slot (darker rectangle at bottom center)
	_poly("Port", _rect(PORT_SIZE, Vector2(0, port_top + PORT_SIZE.y / 2.0)), Color(0.12, 0.14, 0.2))

	# PLACEHOLDER_ART: nav lights (red left, green right), toggled by NavTimer
	nav_light_red = _poly("NavLightRed", _rect(Vector2(12, 12), Vector2(-half_hull.x + 24, -half_hull.y + 24)),
		Color(1, 0.15, 0.1))
	nav_light_green = _poly("NavLightGreen", _rect(Vector2(12, 12), Vector2(half_hull.x - 24, -half_hull.y + 24)),
		Color(0.2, 1, 0.3))
	nav_light_green.visible = false

	# PLACEHOLDER_ART: clamp arms, pivoted at the port's top corners, hanging
	# down along the port sides with a hook pointing inward at the tip
	var clamp_color := Color(0.75, 0.78, 0.82)
	clamp_left = _poly("ClampLeft", PackedVector2Array([
		Vector2(-12, 0), Vector2(0, 0), Vector2(0, CLAMP_LENGTH - 14),
		Vector2(16, CLAMP_LENGTH - 14), Vector2(16, CLAMP_LENGTH), Vector2(-12, CLAMP_LENGTH),
	]), clamp_color)
	clamp_left.position = Vector2(-PORT_SIZE.x / 2.0, port_top)
	clamp_left.z_index = 2  # Over the docked ship (player z_index 1)
	clamp_right = _poly("ClampRight", PackedVector2Array([
		Vector2(12, 0), Vector2(0, 0), Vector2(0, CLAMP_LENGTH - 14),
		Vector2(-16, CLAMP_LENGTH - 14), Vector2(-16, CLAMP_LENGTH), Vector2(12, CLAMP_LENGTH),
	]), clamp_color)
	clamp_right.position = Vector2(PORT_SIZE.x / 2.0, port_top)
	clamp_right.z_index = 2

	# Docking flash over the port (code-only effect, no art needed)
	flash = _poly("DockFlash", _rect(PORT_SIZE + Vector2(40, 40), Vector2(0, port_top + PORT_SIZE.y / 2.0)),
		Color(1, 1, 1))
	flash.z_index = 3
	flash.visible = false

	# "DOCKED" label under the station/ship (code-only, m5x7 gold)
	docked_label = Label.new()
	docked_label.name = "DockedLabel"
	docked_label.text = "DOCKED"
	docked_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	docked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	docked_label.add_theme_font_override("font", DOCKED_FONT)
	docked_label.add_theme_font_size_override("font_size", 48)
	docked_label.add_theme_color_override("font_color", DOCKED_COLOR)
	docked_label.add_theme_color_override("font_outline_color", Color.BLACK)
	docked_label.add_theme_constant_override("outline_size", 8)
	docked_label.size = Vector2(240, 50)
	docked_label.pivot_offset = docked_label.size / 2.0
	docked_label.position = Vector2(-120, half_hull.y + 70)
	docked_label.z_index = 3
	docked_label.visible = false
	add_child(docked_label)
