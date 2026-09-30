# main_menu.gd
extends Control

# Node references
@onready var background_music = $BackgroundMusic
@onready var menu_ui = $MainMenuUi
@onready var credits_panel = $MainMenuCredits
@onready var ship_select = $ShipSelectUi

func _ready() -> void:
	# A finished run's idle pooled nodes (obstacles, shots, explosions, boss)
	# aren't needed while the menu shows; the next run re-creates what it uses
	ObjectPool.clear()

	# Handle input configuration
	configure_input()
	
	if background_music:
		background_music.play()

	# Connect to menu UI signals
	menu_ui.menu_item_selected.connect(_on_menu_item_selected)

	# Connect credits back button
	if credits_panel:
		credits_panel.back_pressed.connect(_on_credits_back_pressed)

	# Ship select ("Start Game" -> choose a SoM -> LAUNCH)
	ship_select.launch_requested.connect(_on_ship_launch_requested)
	ship_select.back_requested.connect(_on_ship_select_back)

func configure_input() -> void:
	# Set mouse mode to visible to ensure proper mouse/touch handling
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_menu_item_selected(item: String) -> void:
	match item:
		"Start Game":
			show_ship_select()
		"Credits":
			show_credits()
		"Quit":
			get_tree().quit()

func start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main_level.tscn")

func show_ship_select() -> void:
	menu_ui.hide()
	# Kiosk: every visitor starts on the first ship, not the previous
	# visitor's pick (GameSession outlives scene changes)
	GameSession.select_ship(0)
	ship_select.open()

func _on_ship_launch_requested(index: int) -> void:
	GameSession.select_ship(index)
	start_game()

# BACK, ui_cancel or the ship select's idle timeout
func _on_ship_select_back() -> void:
	ship_select.hide()
	menu_ui.show()

func show_credits() -> void:
	menu_ui.hide()
	credits_panel.show()

func _on_credits_back_pressed() -> void:
	credits_panel.hide()
	menu_ui.show()
