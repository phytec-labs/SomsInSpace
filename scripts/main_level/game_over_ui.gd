extends Control

signal retry_pressed
signal main_menu_pressed

@onready var height_label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreContainer/HeightLabel
@onready var retry_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/RetryButton
@onready var main_menu_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/MainMenuButton

var buttons: Array[Button]
var current_selection: int = 0

# Style variables
var normal_style: StyleBoxFlat
var highlighted_style: StyleBoxFlat
var normal_color = Color(1, 1, 1)  # White
var highlighted_color = Color(1, 1, 0)  # Yellow

func _ready():
	# Ensure all required nodes are present
	if not retry_button or not main_menu_button:
		push_error("Required buttons not found in game over screen")
		return

	# Initialize buttons array
	buttons = [retry_button, main_menu_button]

	# Get styles from the first button
	normal_style = retry_button.get_theme_stylebox("normal")
	highlighted_style = retry_button.get_theme_stylebox("hover")

	# Configure each button
	for button in buttons:
		# Disable default focus styling
		button.focus_mode = Control.FOCUS_NONE

		# Connect signals
		button.mouse_entered.connect(_on_button_hover.bind(buttons.find(button)))
		button.mouse_exited.connect(_on_button_mouse_exit)
		button.pressed.connect(_on_button_pressed.bind(button))

	# Connect visibility signal
	visibility_changed.connect(_on_visibility_changed)

	# Initially hide the screen
	hide()

func _input(event: InputEvent) -> void:
	if not visible or buttons.is_empty():
		return

	if event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		move_selection(1)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		move_selection(-1)
	elif event.is_action_pressed("ui_accept"):
		select_current_item()

func move_selection(direction: int) -> void:
	if buttons.is_empty():
		return

	current_selection = (current_selection + direction) % buttons.size()
	if current_selection < 0:
		current_selection = buttons.size() - 1
	update_selection()

func update_selection() -> void:
	if buttons.is_empty():
		return

	for i in range(buttons.size()):
		var button = buttons[i]
		if i == current_selection:
			button.add_theme_stylebox_override("normal", highlighted_style)
			button.add_theme_color_override("font_color", highlighted_color)
		else:
			button.add_theme_stylebox_override("normal", normal_style)
			button.add_theme_color_override("font_color", normal_color)

func select_current_item() -> void:
	if buttons.is_empty():
		return

	var selected_button = buttons[current_selection]
	_on_button_pressed(selected_button)

func set_final_height(height: float) -> void:
	if height_label:
		height_label.text = "%d m" % floor(height)

func _on_button_pressed(button: Button) -> void:
	match button:
		retry_button:
			retry_pressed.emit()
		main_menu_button:
			main_menu_pressed.emit()

func _on_button_hover(index: int) -> void:
	current_selection = index
	update_selection()

func _on_button_mouse_exit() -> void:
	# Optional: If you want the selection to stay when mouse exits,
	# leave this empty. Remove this function if you don't need it.
	pass

func _on_visibility_changed() -> void:
	if visible:
		current_selection = 0  # Reset to first option
		update_selection()
