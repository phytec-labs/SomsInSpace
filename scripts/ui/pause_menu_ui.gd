# pause_menu_ui.gd
# Pause overlay shown by main_level.gd while the SceneTree is paused.
# The root node runs with PROCESS_MODE_ALWAYS so it stays interactive.
extends Control

signal resume_pressed
signal main_menu_pressed

@onready var resume_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/ResumeButton
@onready var main_menu_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/MainMenuButton

# Preloaded (rather than relying on the global class_name cache) so the
# script resolves even when .godot/ has not been regenerated.
const MenuButtonGroupScript := preload("res://scripts/ui/menu_button_group.gd")
const IdleReturnScript := preload("res://scripts/ui/idle_return.gd")

## Kiosk: abandon a paused run after this long without input.
const IDLE_TIMEOUT_SECONDS := 60.0

var menu_group: MenuButtonGroupScript
var idle_return: IdleReturnScript

func _ready() -> void:
	# Must keep processing input while the tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Touch activates on release so the rest of the gesture (and the emulated
	# mouse events that follow it) can't reach the player after resuming.
	menu_group = MenuButtonGroupScript.new()
	menu_group.name = "MenuButtonGroup"
	menu_group.use_move_actions = true
	menu_group.activate_touch_on_release = true
	add_child(menu_group)
	menu_group.setup([resume_button, main_menu_button])
	menu_group.button_activated.connect(_on_button_activated)

	visibility_changed.connect(_on_visibility_changed)

	# Kiosk idle timeout. Inherits PROCESS_MODE_ALWAYS from this node, so it
	# keeps counting while the tree is paused. The level's main_menu_pressed
	# handler unpauses the tree before changing scene.
	idle_return = IdleReturnScript.new()
	idle_return.timeout_seconds = IDLE_TIMEOUT_SECONDS
	add_child(idle_return)
	idle_return.idle_timeout.connect(main_menu_pressed.emit)
	hide()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Escape / back closes the pause menu
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_pressed.emit()

func _on_button_activated(_index: int, button: Button) -> void:
	match button:
		resume_button:
			resume_pressed.emit()
		main_menu_button:
			main_menu_pressed.emit()

func _on_visibility_changed() -> void:
	if visible:
		# Default to "Resume" each time the menu opens
		menu_group.select(0)
