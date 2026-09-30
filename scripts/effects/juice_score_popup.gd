# juice_score_popup.gd
# Floating "+N" score text. Pooled via the ObjectPool autoload: acquire it
# under the level, call popup(), and it floats up, fades out and releases
# itself back to the pool (never queue_free()d).
#
# Pause-safe: the tween is bound to this node, so it freezes with the tree.
extends Label

## Seconds from spawn to release
@export var lifetime: float = 0.8
## Pixels floated upward over the lifetime
@export var rise: float = 60.0

var _tween: Tween
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## Show `text` centered on `at` (parent coordinates), tinted `color`, drawn at
## `size_scale` (1 = kill popup, smaller for grazes).
func popup(text_value: String, at: Vector2, color: Color, size_scale: float = 1.0) -> void:
	if _tween:
		_tween.kill()
	text = text_value
	pivot_offset = size / 2.0
	position = at - size / 2.0
	_base_scale = Vector2(size_scale, size_scale)
	scale = _base_scale * 1.3
	modulate = color

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", _base_scale, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:y", position.y - rise, lifetime) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)
	_tween.chain().tween_callback(_release)

func _release() -> void:
	_tween = null
	ObjectPool.release(self)
