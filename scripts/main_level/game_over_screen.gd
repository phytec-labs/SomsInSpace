extends Control

signal retry_pressed
signal main_menu_pressed

@onready var height_label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScoreContainer/HeightLabel
@onready var retry_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/RetryButton
@onready var main_menu_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/MainMenuButton

var current_selection: int = 0
var buttons: Array[Button]

func _ready():
	# Ensure all required nodes are present
	if not retry_button or not main_menu_button:
		push_error("Required buttons not found in game over screen")
		return
		
	# Initialize buttons array
	buttons = [retry_button, main_menu_button]
	
	# Connect button signals
	retry_button.pressed.connect(_on_retry_button_pressed)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	
	# Connect visibility signal
	visibility_changed.connect(_on_visibility_changed)
	
	# Initially hide the screen
	hide()

func _process(_delta):
	if not visible or buttons.is_empty():
		return
		
	# Handle input for menu navigation
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
		move_selection(-1)
	elif Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
		move_selection(1)
	elif Input.is_action_just_pressed("ui_accept"):
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
			button.grab_focus()
			button.modulate = Color(1, 1, 0)  # Yellow tint for selected
		else:
			button.modulate = Color(1, 1, 1)  # Normal color for unselected

func select_current_item() -> void:
	if buttons.is_empty():
		return
		
	match current_selection:
		0:  # Retry button
			_on_retry_button_pressed()
		1:  # Main menu button
			_on_main_menu_button_pressed()

func set_final_height(height: float) -> void:
	if height_label:
		height_label.text = "%d m" % floor(height)

func _on_retry_button_pressed() -> void:
	emit_signal("retry_pressed")

func _on_main_menu_button_pressed() -> void:
	emit_signal("main_menu_pressed")

func _on_visibility_changed() -> void:
	if visible:
		current_selection = 0  # Reset to first option
		update_selection()
