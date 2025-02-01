# credits_ui.gd
extends CenterContainer

signal back_pressed

@onready var back_button = $PanelContainer/MarginContainer/VBoxContainer/BackButton

# Style variables
var normal_style: StyleBoxFlat
var highlighted_style: StyleBoxFlat
var normal_color = Color(1, 1, 1)  # White
var highlighted_color = Color(1, 1, 0)  # Yellow

func _ready() -> void:
	# Get styles from the button
	normal_style = back_button.get_theme_stylebox("normal")
	highlighted_style = back_button.get_theme_stylebox("hover")

	# Configure button
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.mouse_entered.connect(_on_button_hover)
	back_button.mouse_exited.connect(_on_button_mouse_exit)
	back_button.pressed.connect(_on_back_button_pressed)

	# Connect visibility signal
	visibility_changed.connect(_on_visibility_changed)

	# Enable input processing
	set_process_input(true)

	# Set initial style
	update_button_style(false)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()

func update_button_style(highlighted: bool) -> void:
	if highlighted:
		back_button.add_theme_stylebox_override("normal", highlighted_style)
		back_button.add_theme_color_override("font_color", highlighted_color)
	else:
		back_button.add_theme_stylebox_override("normal", normal_style)
		back_button.add_theme_color_override("font_color", normal_color)

func _on_button_hover() -> void:
	update_button_style(true)

func _on_button_mouse_exit() -> void:
	# Keep the button highlighted when mouse exits
	pass

func _on_back_button_pressed() -> void:
	back_pressed.emit()

func _on_visibility_changed() -> void:
	if visible:
		# Highlight the button by default when shown
		update_button_style(true)
