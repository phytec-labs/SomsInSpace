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

# Input cooldown to prevent rapid selection changes
var input_cooldown = false
var cooldown_time = 0.3  # in seconds

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
		print("Button configured: ", button.text)

	# Set initial selection
	update_selection()
	set_process_input(true)

func _process(delta) -> void:
	# Handle cooldown timer
	if input_cooldown:
		cooldown_time -= delta
		if cooldown_time <= 0:
			input_cooldown = false
			cooldown_time = 0.3

func _input(event: InputEvent) -> void:
	if not visible:
		return
		
	# Debug all input events
	print("Input event received: ", event.get_class())
	
	# Handle joypad motion (touchscreen movement)
	if event is InputEventJoypadMotion:
		print("Joypad motion: axis=", event.axis, " value=", event.axis_value)
		
		# For vertical axis (usually axis 1 is vertical, but axis 0 is horizontal)
		if event.axis == 1 and abs(event.axis_value) > 0.5:
			if event.axis_value > 0 and not input_cooldown:  # Down
				print("Joypad DOWN motion detected")
				move_selection(1)
			elif event.axis_value < 0 and not input_cooldown:  # Up
				print("Joypad UP motion detected")
				move_selection(-1)
				
	# Handle joypad button (touchscreen taps)
	elif event is InputEventJoypadButton and event.pressed:
		print("Joypad button pressed: ", event.button_index)
		# Usually button 0 is the "A" button or primary action
		if event.button_index == JOY_BUTTON_A:
			select_current_item()
			
	# Keep original keyboard input handling
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		if not input_cooldown:
			print("DOWN action detected")
			move_selection(1)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		if not input_cooldown:
			print("UP action detected")
			move_selection(-1)
	elif event.is_action_pressed("ui_accept"):
		print("ACCEPT action detected")
		select_current_item()

func move_selection(direction: int) -> void:
	if buttons.is_empty():
		return
		
	# Set cooldown to prevent rapid selection
	input_cooldown = true
	
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
	print("Button selected: ", selected_button.text)
	menu_item_selected.emit(selected_button.text)

func _on_button_pressed(item: String) -> void:
	print("Button pressed: ", item)
	menu_item_selected.emit(item)

func _on_button_hover(index: int) -> void:
	current_selection = index
	update_selection()

func _on_button_mouse_exit() -> void:
	# Optional: If you want the selection to stay when mouse exits,
	# leave this empty. Remove this function if you don't need it.
	pass
