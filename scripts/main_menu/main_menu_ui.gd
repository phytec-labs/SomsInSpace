# main_menu_ui.gd
extends CenterContainer

signal menu_item_selected(item: String)

var buttons: Array = []
var current_selection: int = 0

# Style variables
var normal_style: StyleBoxFlat
var highlighted_style: StyleBoxFlat
var normal_color = Color(1, 1, 1)  # White
var highlighted_color = Color(1, 1, 0)  # Yellow

func _ready() -> void:
	# Get both styles from the first button
	var base_button = $PanelContainer/MarginContainer/MenuContainer/StartGameButton
	normal_style = base_button.get_theme_stylebox("normal")

	# Get the highlighted style from the theme
	highlighted_style = base_button.get_theme_stylebox("hover")

	var menu_container = $PanelContainer/MarginContainer/MenuContainer
	buttons = menu_container.get_children()

	# Configure each button
	for button in buttons:
		# Disable default focus styling
		button.focus_mode = Control.FOCUS_NONE

		# Connect signals
		button.mouse_entered.connect(_on_button_hover.bind(buttons.find(button)))
		button.mouse_exited.connect(_on_button_mouse_exit)
		button.pressed.connect(_on_button_pressed.bind(button.text))

	# Set initial selection
	update_selection()
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_down"):
		move_selection(1)
	elif event.is_action_pressed("ui_up"):
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
	if buttons.is_empty() or current_selection < 0 or current_selection >= buttons.size():
		return

	var selected_button = buttons[current_selection]
	menu_item_selected.emit(selected_button.text)

func _on_button_pressed(item: String) -> void:
	menu_item_selected.emit(item)

func _on_button_hover(index: int) -> void:
	current_selection = index
	update_selection()

func _on_button_mouse_exit() -> void:
	# Optional: If you want the selection to stay when mouse exits,
	# leave this empty. Remove this function if you don't need it.
	pass
