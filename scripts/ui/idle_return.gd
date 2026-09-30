# idle_return.gd
# Kiosk idle timer for a UI screen. Add it as a child of the screen's root
# Control (ideally as the LAST child, so its _input runs before siblings that
# may mark events as handled). While the parent is visible in the tree it
# counts down timeout_seconds; any input event resets the countdown. When it
# reaches zero it emits idle_timeout ONCE and then stays idle until the parent
# is shown again or restart() is called, so a screen change triggered by the
# emit can't re-fire it.
#
# Pause behaviour: process_mode is set to PROCESS_MODE_INHERIT on purpose.
# Hosts shown while the SceneTree is paused (the pause menu) must themselves
# run with PROCESS_MODE_ALWAYS; this node then inherits that and keeps
# counting/receiving input while paused. Hosts that are only shown while the
# tree runs (results screen, credits) need nothing special.
class_name IdleReturn
extends Node

signal idle_timeout

## Seconds without input (while the host is visible) before idle_timeout.
@export var timeout_seconds: float = 60.0
## When false the timer neither counts nor fires.
@export var active: bool = true

# Joypad axis values below this are treated as stick drift, not activity.
const JOY_AXIS_DEADZONE := 0.2

var _remaining: float = 0.0
var _fired: bool = false


func _init() -> void:
	name = "IdleReturn"


func _ready() -> void:
	# Inherit from the host (see header): ALWAYS under the pause menu.
	set_process_mode(Node.PROCESS_MODE_INHERIT)
	restart()


func _enter_tree() -> void:
	var host := get_parent() as CanvasItem
	if host and not host.visibility_changed.is_connected(_on_host_visibility_changed):
		host.visibility_changed.connect(_on_host_visibility_changed)


func _exit_tree() -> void:
	var host := get_parent() as CanvasItem
	if host and host.visibility_changed.is_connected(_on_host_visibility_changed):
		host.visibility_changed.disconnect(_on_host_visibility_changed)


## Resets the countdown to timeout_seconds and re-arms the one-shot emit.
func restart() -> void:
	_remaining = timeout_seconds
	_fired = false


## Seconds left before idle_timeout (for debugging/tests).
func get_time_left() -> float:
	return _remaining


func _process(delta: float) -> void:
	if not active or _fired or not _host_visible():
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_remaining = 0.0
		_fired = true
		idle_timeout.emit()


# _input sees touch, mouse, key, joypad and drag events before GUI controls
# (Buttons, the onscreen keyboard keys) consume them, as well as synthetic
# events injected with Input.parse_input_event().
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and absf(event.axis_value) < JOY_AXIS_DEADZONE:
		return
	if _host_visible():
		restart()


# visibility_changed also fires when an ancestor of the host changes
func _on_host_visibility_changed() -> void:
	if _host_visible():
		restart()


func _host_visible() -> bool:
	var host := get_parent() as CanvasItem
	return host != null and host.is_visible_in_tree()
