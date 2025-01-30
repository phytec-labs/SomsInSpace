# main_menu.gd (updated version)
extends Control

# Node references
@onready var background_music = $BackgroundMusic
@onready var menu_ui = $MainMenuUi

func _ready() -> void:
	if background_music:
		background_music.play()
	else:
		print("Warning: background_music node not found")

	# Connect to menu UI signals
	menu_ui.menu_item_selected.connect(_on_menu_item_selected)

func _on_menu_item_selected(item: String) -> void:
	match item:
		"Start Game":
			start_game()
		"Options":
			open_options()
		"Credits":
			show_credits()
		"Quit":
			get_tree().quit()

func start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main_level.tscn")

func open_options() -> void:
	print("Opening options...")
	# Implement options menu

func show_credits() -> void:
	print("Showing credits...")
	# Implement credits screen
