# coin_pop.gd
# Quick "pop" where an energy coin is collected (main_level.gd, next to the
# gold "+5" popup): a bright warm flash (a white-gold core inside a softer
# gold halo, drawn by a child with additive blending so it always reads as
# light, on the pale ground sky and on the dark space sky alike, never as a
# grey disc) that collapses fast, a gold ring expanding outward, and
# a few sparks flying out, all over `duration` (0.24 s). Drawn with _draw()
# (no texture, no shader; the flash child uses a CanvasItemMaterial).
# Pooled via the ObjectPool autoload: acquire it under the level, call
# burst(), and it releases itself back to the pool when done (never
# queue_free()d). The collected coin itself goes back to its pool at once.
#
# Pause-safe: the time is accumulated in _process().
extends Node2D

## Seconds from burst to release
@export var duration: float = 0.24
## Coin radius the flash and ring start from (px)
@export var start_radius: float = 16.0
## Radius the ring reaches (px)
@export var ring_radius: float = 42.0
## Number of sparks
@export var spark_count: int = 6
## Flash core (additive) and its softer halo (additive)
@export var flash_color: Color = Color(1.0, 0.97, 0.8)
@export var flash_halo_color: Color = Color(1.0, 0.82, 0.32)
## Fraction of `duration` the flash lasts
@export var flash_fraction: float = 0.3
@export var ring_color: Color = Color(1.0, 0.8, 0.25)
@export var spark_color: Color = Color(1.0, 0.92, 0.55)

var _t: float = 0.0
var _spark_offset: float = 0.0
var _flash: Node2D

# The flash child is built here (not in _ready) so burst() works even
# before the node enters the tree
func _init() -> void:
	# Additive flash under the ring and sparks
	_flash = Node2D.new()
	_flash.show_behind_parent = true
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = mat
	_flash.draw.connect(_draw_flash)
	add_child(_flash)

func _ready() -> void:
	z_index = 6
	z_as_relative = false
	set_process(false)

## Pop at `at` (global position)
func burst(at: Vector2) -> void:
	global_position = at
	_t = 0.0
	_spark_offset = randf() * TAU
	set_process(true)
	queue_redraw()
	_flash.queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		set_process(false)
		ObjectPool.release(self)
		return
	queue_redraw()
	_flash.queue_redraw()

# Flash (additive, so it only ever brightens): a white-gold core inside a
# thin gold halo, both near full strength and collapsing (shrinking to
# nothing) over the first flash_fraction of the pop instead of fading, so
# there is never a large dim disc (which reads as grey/brown on dark skies)
func _draw_flash() -> void:
	var f := clampf(_t / (duration * flash_fraction), 0.0, 1.0)
	if f >= 1.0:
		return
	var shrink := 1.0 - f * f
	var hc := flash_halo_color
	hc.a = 1.0 - 0.3 * f
	_flash.draw_circle(Vector2.ZERO, start_radius * shrink, hc)
	var cc := flash_color
	cc.a = 1.0 - 0.4 * f
	_flash.draw_circle(Vector2.ZERO, start_radius * 0.7 * shrink, cc)

func _draw() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	var out := 1.0 - (1.0 - k) * (1.0 - k)  # ease out
	# Ring
	var rc := ring_color
	rc.a = 1.0 - k
	draw_arc(Vector2.ZERO, lerpf(start_radius, ring_radius, out), 0.0, TAU, 32, rc,
		lerpf(3.0, 1.0, k), true)
	# Sparks
	var sc := spark_color
	sc.a = 1.0 - k
	# Sparks outrun the ring
	var r0 := lerpf(start_radius * 0.8, ring_radius * 1.3, out)
	var r1 := r0 + lerpf(10.0, 4.0, k)
	for i in spark_count:
		var dir := Vector2.from_angle(_spark_offset + TAU * i / spark_count)
		draw_line(dir * r0, dir * r1, sc, 2.5, true)
