# main_menu_ui.gd
extends CenterContainer

signal menu_item_selected(item: String)

var menu_items = ["Start Game", "Options", "Credits", "Quit"]
var buttons: Array[Button] = []
var current_selection: int = 0

func _ready() -> void:
	create_menu_buttons()

func create_menu_buttons() -> void:
	var menu_container = $PanelContainer/MarginContainer/MenuContainer
	
	# Clear existing buttons
	for child in menu_container.get_children():
		child.queue_free()
	buttons.clear()
	
	# Create new buttons
	for item in menu_items:
		var button = Button.new()
		button.text = item
		button.pressed.connect(_on_button_pressed.bind(item))
		button.mouse_entered.connect(_on_button_hover.bind(buttons.size()))
		menu_container.add_child(button)
		buttons.append(button)
	
	update_selection()

func _process(_delta: float) -> void:
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
	if buttons.is_empty() or current_selection < 0 or current_selection >= buttons.size():
		return
	
	menu_item_selected.emit(menu_items[current_selection])

func _on_button_pressed(item: String) -> void:
	menu_item_selected.emit(item)

func _on_button_hover(index: int) -> void:
	current_selection = index
	update_selection()
