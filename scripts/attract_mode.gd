# attract_mode.gd
# Autoload (AttractMode): kiosk attract mode. The main menu starts a demo run
# after its idle timeout by setting GameSession.demo_mode and loading the
# level; this node notices the level (polling get_tree().current_scene) and
# turns it into a self-playing demo:
#   - AttractOverlay (scenes/ui/attract_overlay.tscn): blinking
#     "DEMO / TOUCH TO PLAY" banner that swallows all input
#   - AttractAutopilot (scripts/attract_autopilot.gd): flies and fires
# The demo ends, back to the main menu, when:
#   - a visitor presses anything (touch, mouse button, key, joypad button):
#     the menu then opens straight on ship select
#   - the run ends (GAME_OVER / VICTORY), BEFORE the results screen can show,
#     so a demo never enters a name or records a high score
#   - demo_max_seconds have passed
# Nothing in the level knows about the demo.
extends Node

const OVERLAY_SCENE := preload("res://scenes/ui/attract_overlay.tscn")
const AutopilotScript := preload("res://scripts/attract_autopilot.gd")
const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const LEVEL_SCRIPT_SUFFIX := "main_level.gd"
const LEVEL_NODE_NAME := "MainLevel"

## A demo lasts at most this long (seconds of level time since it started)
@export var demo_max_seconds: float = 75.0
## demo_mode set but no level shows up (failed load) for this long: give up
const LEVEL_WAIT_TIMEOUT := 2.0

## Emitted when a demo ends; reason is "input", "run_over" or "timeout"
signal demo_ended(reason: String)

var _level: Node = null
var _overlay: CanvasLayer = null
var _autopilot: Node = null
var _elapsed: float = 0.0
var _waiting_for_level: float = 0.0
var _exiting: bool = false
var _game_over_state: int = -1
var _victory_state: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_demo_running() -> bool:
	return is_instance_valid(_level) and GameSession.demo_mode and not _exiting


func _process(delta: float) -> void:
	var scene := get_tree().current_scene

	if not GameSession.demo_mode:
		if _level != null:
			_detach()
		return

	if scene == null or not is_level(scene):
		# Between scenes (change_scene_to_file leaves current_scene null for a
		# frame) or still on the menu that requested the demo
		if _level != null and not is_instance_valid(_level):
			_detach()
		_waiting_for_level += delta
		if _waiting_for_level > LEVEL_WAIT_TIMEOUT and not _exiting:
			push_warning("AttractMode: demo requested but no level loaded; cancelling")
			GameSession.demo_mode = false
			_waiting_for_level = 0.0
		return
	_waiting_for_level = 0.0

	if scene != _level:
		_attach(scene)

	if _exiting:
		return

	# Leave before the results screen (game over shows it after 1 s, victory
	# after the docking sequence)
	var state = _level.get("current_state")
	if state != null and (state == _game_over_state or state == _victory_state):
		exit_demo("run_over")
		return

	if not get_tree().paused:
		_elapsed += delta
	if _elapsed >= demo_max_seconds:
		exit_demo("timeout")


## True for the main level scene root.
static func is_level(node: Node) -> bool:
	if node == null:
		return false
	var script: Script = node.get_script()
	if script and script.resource_path.ends_with(LEVEL_SCRIPT_SUFFIX):
		return true
	return node.name == LEVEL_NODE_NAME


## End the demo and go back to the main menu. reason "input" (a visitor
## pressed something) opens ship select there.
func exit_demo(reason: String = "input") -> void:
	if _exiting or not GameSession.demo_mode:
		return
	_exiting = true
	GameSession.demo_mode = false
	GameSession.open_ship_select_on_menu = reason == "input"
	get_tree().paused = false
	if is_instance_valid(_autopilot):
		_autopilot.set_physics_process(false)
	# The menu clears ObjectPool itself
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
	demo_ended.emit(reason)


func _attach(level: Node) -> void:
	_detach()
	_level = level
	_elapsed = 0.0
	_exiting = false

	var states = _get_level_states(level)
	_game_over_state = states.get("GAME_OVER", -1)
	_victory_state = states.get("VICTORY", -1)

	_autopilot = AutopilotScript.new()
	_autopilot.setup(level)
	level.add_child(_autopilot)

	# Added last so its _input runs before the HUD's / level's (pause button,
	# Escape) and swallows everything
	_overlay = OVERLAY_SCENE.instantiate()
	_overlay.name = "AttractOverlay"
	level.add_child(_overlay)
	_overlay.exit_requested.connect(exit_demo.bind("input"))


func _detach() -> void:
	# Both are children of the level and normally die with it
	for node in [_overlay, _autopilot]:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	_overlay = null
	_autopilot = null
	_level = null
	_exiting = false


func _get_level_states(level: Node) -> Dictionary:
	var script: Script = level.get_script()
	if script:
		var constants := script.get_script_constant_map()
		if constants.has("GameState"):
			return constants["GameState"]
	return {}
