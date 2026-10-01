# docking_station.gd
# Orbital station for the victory sequence (spawned by main_level.gd when the
# boss is defeated). The ship lands on the station's central pad.
#
# Art: sprites/space_station_1.png (1024x341, master 2172x724; top-down, wide
# and low, landing pad with an orange crosshair in the middle) on the "Hull"
# Sprite2D at 0.6641 (680x226 px on screen; set in docking_station.tscn). DockPoint sits on the
# crosshair; PAD_RECT is the dark pad rectangle in station-local px.
#
# play_docking(ship) runs the whole choreography with node-bound tweens (so it
# freezes with the tree and dies with the level):
#   1. wait start_delay (the boss death sequence)
#   2. descend from start_y to dock_y over descend_time (ease out)
#   3. emit ready_for_ship; the level calls
#      player.fly_to(get_dock_position(), ship_fly_time, landing_scale), so
#      the ship flies over the pad and shrinks onto it (reads as descending);
#      the station waits for the ship's `arrived` signal (or ship_fly_time if
#      the ship has none)
#   4. touchdown: emit touchdown (the level shakes the camera), a green ring
#      pulses out from the crosshair (ring_time), white flash over the pad
#      (flash_time), "DOCKED" label pop under the station
#   5. wait finish_delay, emit docking_finished
# Total from boss death to docking_finished: ~7.45 s with the defaults.
extends Node2D

signal ready_for_ship
signal touchdown
signal docking_finished

@export_group("Timeline")
## Wait before the station appears (boss death sequence, ~1.5 s)
@export var start_delay: float = 1.5
@export var descend_time: float = 2.0
## Duration the level passes to player.fly_to()
@export var ship_fly_time: float = 2.4
## Touchdown ring pulse (runs alongside the flash and label pop)
@export var ring_time: float = 0.4
@export var flash_time: float = 0.2
## Wait after the DOCKED pop before docking_finished
@export var finish_delay: float = 1.2

@export_group("Placement")
@export var start_y: float = -300.0
@export var dock_y: float = 260.0
## Ship scale on the pad (the level passes it to player.fly_to): the largest
## ship's visible art (~127x186 local px) at 0.36 is ~46x67 px, inside the
## 144x80 px pad with ~6 px to spare top and bottom
@export var landing_scale: float = 0.36

const DOCKED_FONT := preload("res://fonts/m5x7.ttf")
const DOCKED_COLOR := Color(1, 0.8, 0.2)
const RING_COLOR := Color(0.3, 1.0, 0.45)

# Landing pad (dark rectangle, texture px 404..621 x 111..231 at the Hull's
# 0.6641 scale) in station-local px, and the touchdown ring's radii
const PAD_RECT := Rect2(-71.7, -39.5, 144.1, 79.7)
const RING_START_RADIUS := 10.0
const RING_END_RADIUS := 90.0
const RING_WIDTH := 4.0
const RING_SEGMENTS := 32

@onready var dock_point: Marker2D = $DockPoint
@onready var hull: Sprite2D = $Hull

var flash: Polygon2D
var ring: Line2D
var docked_label: Label

var _ship: Node2D = null
var _tween: Tween
var _ring_tween: Tween
var _docking: bool = false
var _ship_arrived: bool = false

func _ready() -> void:
	_build_effects()

## Station-global position the ship's origin should fly to
func get_dock_position() -> Vector2:
	return dock_point.global_position

## Landing pad rectangle in global coordinates (station is never rotated)
func get_pad_rect() -> Rect2:
	return Rect2(to_global(PAD_RECT.position), PAD_RECT.size * global_scale)

func play_docking(ship: Node2D) -> void:
	if _docking:
		return
	_docking = true
	_ship = ship
	_ship_arrived = false
	position.y = start_y
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
	_on_touchdown()

func _on_touchdown() -> void:
	# Green ring expanding from the crosshair (under the ship), fading out
	ring.visible = true
	_set_ring_radius(RING_START_RADIUS)
	ring.modulate.a = 1.0
	_ring_tween = create_tween()
	_ring_tween.set_parallel(true)
	_ring_tween.tween_method(_set_ring_radius, RING_START_RADIUS, RING_END_RADIUS, ring_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(ring, "modulate:a", 0.0, ring_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_ring_tween.chain().tween_callback(ring.hide)

	# Flash over the pad, DOCKED pops under the station
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
	# Effects are running; the level shakes the camera on this
	touchdown.emit()

func _set_ring_radius(radius: float) -> void:
	var points := PackedVector2Array()
	for i in RING_SEGMENTS:
		points.append(Vector2.from_angle(TAU * i / float(RING_SEGMENTS)) * radius)
	ring.points = points

func _on_finished() -> void:
	flash.visible = false
	docking_finished.emit()

# --- Code-only effects (no art needed) ---------------------------------------

func _build_effects() -> void:
	var pad_center := PAD_RECT.get_center()

	# Touchdown ring around the crosshair, grown in _on_touchdown(). Drawn
	# after the hull (above the pad) and below the ship (player z_index 1).
	ring = Line2D.new()
	ring.name = "TouchdownRing"
	ring.width = RING_WIDTH
	ring.default_color = RING_COLOR
	ring.closed = true
	ring.antialiased = true
	ring.position = dock_point.position
	ring.visible = false
	add_child(ring)

	# Touchdown flash over the pad
	var h := PAD_RECT.size / 2.0 + Vector2(10, 10)
	flash = Polygon2D.new()
	flash.name = "DockFlash"
	flash.polygon = PackedVector2Array([
		pad_center + Vector2(-h.x, -h.y), pad_center + Vector2(h.x, -h.y),
		pad_center + Vector2(h.x, h.y), pad_center + Vector2(-h.x, h.y)])
	flash.color = Color(1, 1, 1)
	flash.z_index = 3
	flash.visible = false
	add_child(flash)

	# "DOCKED" label under the station (m5x7 gold)
	var hull_half_height := hull.texture.get_height() * hull.scale.y / 2.0 if hull.texture else 113.0
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
	docked_label.position = Vector2(-120, hull_half_height + 12.0)
	docked_label.z_index = 3
	docked_label.visible = false
	add_child(docked_label)
