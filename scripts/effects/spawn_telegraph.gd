# spawn_telegraph.gd
# Warning marker shown where a wave group is about to enter the screen.
# WaveManager acquires it from the ObjectPool, calls start(), and it releases
# itself after `duration` seconds. The chevron points in `direction` (toward
# where the formation will fly in); the whole marker blinks.
#
# Pause-safe: timing is accumulated in _process().
#
# PLACEHOLDER_ART: scenes/effects/spawn_telegraph.tscn draws a yellow
# Polygon2D chevron plus a "!" Label; replace with a 96x96 transparent
# 2-3 frame yellow warning sheet (see docs/ART_SWAP_TRACKER.md).
extends Node2D

const BLINK_RATE: float = 8.0  # Toggles per second

@onready var chevron: Node2D = $Chevron

var duration: float = 0.5
var _elapsed: float = 0.0

# position: where to show it (caller's coordinates); direction: entry heading
func start(at: Vector2, show_for: float, direction: Vector2 = Vector2.DOWN) -> void:
	position = at
	duration = maxf(show_for, 0.05)
	_elapsed = 0.0
	if chevron:
		chevron.rotation = (direction if direction != Vector2.ZERO else Vector2.DOWN).angle() - PI / 2.0
	modulate.a = 1.0
	show()

func _process(delta: float) -> void:
	_elapsed += delta
	modulate.a = 1.0 if int(_elapsed * BLINK_RATE) % 2 == 0 else 0.35
	if _elapsed >= duration:
		ObjectPool.release(self)
