# enemy_health_bar.gd
# Mini health bar under a tanky enemy (Obstacle creates one per instance, see
# Obstacle.health_bar_threshold). It is a child of the obstacle but
# top_level, so it ignores the obstacle's rotation and scale (stays
# horizontal and the same size under spinning asteroids, the 2.5x blimp and
# the hit scale punch); it follows the obstacle's global position here, each
# frame, only while shown.
#
# PLACEHOLDER_ART: code-only (two ColorRects: dark back, red -> yellow fill).
# A 40x5 frame + fill texture (NinePatchRect / TextureProgressBar) could
# replace them; keep the fill's width driven by set_fraction().
extends Node2D

const WIDTH: float = 40.0
const HEIGHT: float = 5.0
const COLOR_LOW := Color(1.0, 0.15, 0.1)   # Nearly dead
const COLOR_HIGH := Color(1.0, 0.9, 0.2)   # Full health

@onready var back: ColorRect = $Back
@onready var fill: ColorRect = $Fill

## Pixels below the followed node's origin (set by Obstacle when shown)
var offset_y: float = 0.0
var _target: Node2D

func _ready() -> void:
	top_level = true
	back.size = Vector2(WIDTH, HEIGHT)
	back.position = Vector2(-WIDTH / 2.0, -HEIGHT / 2.0)
	fill.position = back.position
	fill.size = Vector2(WIDTH, HEIGHT)
	hide_bar()

## Start following `target` (offset_y px below its origin) and show the bar
func show_for(target: Node2D, below: float) -> void:
	_target = target
	offset_y = below
	_follow()
	show()
	set_process(true)

func hide_bar() -> void:
	hide()
	set_process(false)

## 0..1 of max health
func set_fraction(fraction: float) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	fill.size.x = WIDTH * f
	fill.color = COLOR_LOW.lerp(COLOR_HIGH, f)

func get_fraction() -> float:
	return fill.size.x / WIDTH

# Children process after their parent, so this runs after the obstacle moved
func _process(_delta: float) -> void:
	_follow()

func _follow() -> void:
	if is_instance_valid(_target):
		global_position = _target.global_position + Vector2(0.0, offset_y)
