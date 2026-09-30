# juice_camera_shake.gd
# Camera2D script for the level's GameCamera: trauma-style screen shake.
#
# The camera sits at the viewport center with the default drag-center anchor,
# so at rest the view is exactly the unshaken 720x1280 viewport; the shake
# only ever touches `offset`. CanvasLayers (HUD, pause menu, results screen)
# ignore the camera and never shake.
#
# shake(strength, duration): strength is trauma in 0..1 (1 = max_offset),
# the offset is max_offset * trauma^trauma_power in a random direction each
# frame, and the trauma decays linearly to 0 over `duration`. Overlapping
# shakes keep the stronger trauma and the longer remaining time.
#
# Pause-safe: runs in _process (inherits the tree's pause), and the offset is
# zeroed while paused so the frozen view is never left displaced.
extends Camera2D

## Largest offset (px) at trauma 1.0
@export var max_offset: float = 12.0
## Offset = max_offset * trauma^trauma_power (2 = classic trauma curve)
@export var trauma_power: float = 2.0

var _trauma: float = 0.0
var _time_left: float = 0.0
var _decay_rate: float = 0.0

func _ready() -> void:
	offset = Vector2.ZERO
	set_process(false)

func shake(strength: float, duration: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.0 or duration <= 0.0:
		return
	_trauma = maxf(_trauma, strength)
	_time_left = maxf(_time_left, duration)
	_decay_rate = _trauma / _time_left
	set_process(true)

## Current trauma (0 = at rest); for tests / debugging
func get_trauma() -> float:
	return _trauma

func stop_shake() -> void:
	_trauma = 0.0
	_time_left = 0.0
	offset = Vector2.ZERO
	set_process(false)

func _process(delta: float) -> void:
	_time_left -= delta
	_trauma -= _decay_rate * delta
	if _trauma <= 0.0 or _time_left <= 0.0:
		stop_shake()
		return
	var amount := max_offset * pow(_trauma, trauma_power)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount

func _notification(what: int) -> void:
	# Don't leave the view displaced behind the pause menu; the shake resumes
	# (next _process) once unpaused
	if what == NOTIFICATION_PAUSED:
		offset = Vector2.ZERO
