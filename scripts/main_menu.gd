# main_menu.gd
extends Control

# Node references
@onready var background_music = $BackgroundMusic
@onready var menu_ui = $MainMenuUi
@onready var credits_panel = $MainMenuCredits

func _ready() -> void:
	# Handle input configuration
	configure_input()
	
	if background_music:
		background_music.play()

	# Connect to menu UI signals
	menu_ui.menu_item_selected.connect(_on_menu_item_selected)

	# Connect credits back button
	if credits_panel:
		credits_panel.back_pressed.connect(_on_credits_back_pressed)

func configure_input() -> void:
	# Set mouse mode to visible to ensure proper mouse/touch handling
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_menu_item_selected(item: String) -> void:
	match item:
		"Start Game":
			start_game()
		"Credits":
			show_credits()
		"Quit":
			get_tree().quit()

func start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main_level.tscn")

func show_credits() -> void:
	menu_ui.hide()
	credits_panel.show()

func _on_credits_back_pressed() -> void:
	credits_panel.hide()
	menu_ui.show()
