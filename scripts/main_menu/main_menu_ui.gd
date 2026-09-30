# main_menu_ui.gd
extends CenterContainer

signal menu_item_selected(item: String)

@onready var menu_container = $VBoxContainer/PanelContainer/MarginContainer/MenuContainer

# Preloaded (rather than relying on the global class_name cache) so the
# script resolves even when .godot/ has not been regenerated.
const MenuButtonGroupScript := preload("res://scripts/ui/menu_button_group.gd")

var menu_group: MenuButtonGroupScript

func _ready() -> void:
	# Navigation, highlight, hover and touch handling for the menu buttons
	menu_group = MenuButtonGroupScript.new()
	menu_group.name = "MenuButtonGroup"
	# Touch activates on release (inside the same button) so one tap fires
	# exactly once and the rest of the gesture can't leak into the next scene.
	menu_group.activate_touch_on_release = true
	add_child(menu_group)
	menu_group.setup(menu_container.get_children())
	menu_group.button_activated.connect(_on_button_activated)

func _on_button_activated(_index: int, button: Button) -> void:
	menu_item_selected.emit(button.text)
