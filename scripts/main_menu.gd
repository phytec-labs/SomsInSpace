extends Control

# Menu options and current selection
@onready var background_music = $BackgroundMusic
var menu_items = ["Start Game", "Options", "Credits", "Quit"]
var current_selection = 0

func _ready():
	print("Menu items count: ", menu_items.size())
	print("Current selection: ", current_selection)
	if background_music:
		background_music.play()
	else:
		print("Warning: background_music node not found")
	update_menu_display()

func _process(_delta):
	# Handle keyboard input
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
		move_selection(-1)
	elif Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
		move_selection(1)
	elif Input.is_action_just_pressed("ui_accept"):
		select_current_item()

func move_selection(direction):
	# Ensure menu_items is initialized
	if menu_items.size() == 0:
		print("Warning: menu_items is empty")
		return

	# Update the selected item
	current_selection = (current_selection + direction) % menu_items.size()
	if current_selection < 0:
		current_selection = menu_items.size() - 1
	update_menu_display()

func update_menu_display():
	# Clear existing menu items
	for child in $MenuContainer.get_children():
		child.queue_free()

	# Create menu items
	for i in range(menu_items.size()):
		var item = Label.new()
		item.text = menu_items[i]
		if i == current_selection:
			item.add_theme_color_override("font_color", Color(1, 1, 0))  # Yellow for selected
		else:
			item.add_theme_color_override("font_color", Color(1, 1, 1))  # White for unselected
		$MenuContainer.add_child(item)

func select_current_item():
	# Add bounds checking
	if current_selection < 0 or current_selection >= menu_items.size():
		print("Error: current_selection out of bounds")
		return

	match menu_items[current_selection]:
		"Start Game":
			start_game()
		"Options":
			open_options()
		"Credits":
			show_credits()
		"Quit":
			get_tree().quit()

func start_game():
	# Load the main level scene
	print("Starting game...")
	get_tree().change_scene_to_file("res://main_level.tscn")

func open_options():
	print("Opening options...")
	# Implement options menu

func show_credits():
	print("Showing credits...")
	# Implement credits screen
