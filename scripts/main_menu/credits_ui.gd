# credits_ui.gd
extends CenterContainer

signal back_pressed

@onready var back_button = $PanelContainer/MarginContainer/VBoxContainer/BackButton

# Preloaded (rather than relying on the global class_name cache) so the
# script resolves even when .godot/ has not been regenerated.
const MenuButtonGroupScript := preload("res://scripts/ui/menu_button_group.gd")
const IdleReturnScript := preload("res://scripts/ui/idle_return.gd")

## Kiosk: close the credits after this long without input.
const IDLE_TIMEOUT_SECONDS := 30.0

var menu_group: MenuButtonGroupScript
var idle_return: IdleReturnScript

func _ready() -> void:
	# Highlight/touch handling for the single Back button. Touch activates on
	# release so the rest of the gesture can't hit the main menu buttons that
	# become visible once the credits panel hides.
	menu_group = MenuButtonGroupScript.new()
	menu_group.name = "MenuButtonGroup"
	menu_group.activate_touch_on_release = true
	add_child(menu_group)
	# Start unhighlighted; highlighted when shown or hovered
	menu_group.setup([back_button], false)
	menu_group.button_activated.connect(_on_button_activated)

	# Connect visibility signal
	visibility_changed.connect(_on_visibility_changed)

	# Kiosk idle timeout (added last so its _input runs before siblings')
	idle_return = IdleReturnScript.new()
	idle_return.timeout_seconds = IDLE_TIMEOUT_SECONDS
	add_child(idle_return)
	idle_return.idle_timeout.connect(_on_back_button_pressed)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# ui_accept is handled (and consumed) by the MenuButtonGroup
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()

func _on_button_activated(_index: int, _button: Button) -> void:
	_on_back_button_pressed()

func _on_back_button_pressed() -> void:
	back_pressed.emit()

func _on_visibility_changed() -> void:
	if visible:
		# Highlight the button by default when shown
		menu_group.select(0)
