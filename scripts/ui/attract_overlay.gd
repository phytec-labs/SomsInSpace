# attract_overlay.gd
# "DEMO / TOUCH TO PLAY" banner shown over the level while the attract-mode
# demo runs (added by the AttractMode autoload as the level's LAST child, so
# its _input runs before the HUD's and the level's). It swallows every input
# event so the demo can't be steered, paused (HUD pause button, Escape) or
# fired, and emits exit_requested for a real press: touch, mouse button, key
# or joypad button. Mouse motion and joypad axis noise are swallowed but never
# end the demo.
extends CanvasLayer

signal exit_requested

## Blink period of the "TOUCH TO PLAY" text, seconds
@export var blink_period: float = 1.0

@onready var banner: Control = $InputCatcher/Banner


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# Hard blink (on 65 % of the period) reads better from across a booth
	# than a soft fade
	var t := fmod(Time.get_ticks_msec() / 1000.0, blink_period) / blink_period
	banner.modulate.a = 1.0 if t < 0.65 else 0.15


func _input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if is_exit_event(event):
		exit_requested.emit()


## True for input that means "a visitor wants to play".
static func is_exit_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton:
		return event.pressed
	return false
