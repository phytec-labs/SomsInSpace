# main_menu.gd
extends Control

# Node references
@onready var background_music = $BackgroundMusic
@onready var menu_ui = $MainMenuUi
@onready var credits_panel = $MainMenuCredits

func _ready() -> void:
	if background_music:
		background_music.play()
	else:
		print("Warning: background_music node not found")

	# Connect to menu UI signals
	menu_ui.menu_item_selected.connect(_on_menu_item_selected)

	# Connect credits back button
	if credits_panel:
		credits_panel.back_pressed.connect(_on_credits_back_pressed)

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
	menu_ui.hide()
	credits_panel.show()

func _on_credits_back_pressed() -> void:
	credits_panel.hide()
	menu_ui.show()
