# main_menu.gd
extends Control

# Preloaded (rather than relying on the global class_name cache) so the
# script resolves even when .godot/ has not been regenerated.
const IdleReturnScript := preload("res://scripts/ui/idle_return.gd")

## Kiosk attract mode: seconds without input on the menu list before the game
## starts playing itself (AttractMode autoload). Only counts while the list is
## showing (not ship select or credits, whose own idle timeouts come back to
## the list and so re-arm it).
@export var attract_idle_seconds: float = 20.0

# Node references
@onready var background_music = $BackgroundMusic
@onready var menu_ui = $MainMenuUi
@onready var credits_panel = $MainMenuCredits
@onready var ship_select = $ShipSelectUi

var attract_idle: IdleReturnScript

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

	# Attract mode timer on the menu list (added after MainMenuUi's own
	# children, so it is the list's last child as IdleReturn expects). Starts
	# fresh whenever the list is shown, including after a demo ends.
	attract_idle = IdleReturnScript.new()
	attract_idle.name = "AttractIdle"
	attract_idle.timeout_seconds = attract_idle_seconds
	menu_ui.add_child(attract_idle)
	attract_idle.idle_timeout.connect(_on_attract_idle_timeout)

	# A visitor touched the screen during the demo: straight to ship select
	if GameSession.open_ship_select_on_menu:
		GameSession.open_ship_select_on_menu = false
		show_ship_select()

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

# Nobody touched the menu list for attract_idle_seconds: play a demo run
# with the first ship (AttractMode takes over once the level is loaded)
func _on_attract_idle_timeout() -> void:
	if not menu_ui.is_visible_in_tree():
		return
	GameSession.demo_mode = true
	GameSession.select_ship(0)
	start_game()

func show_ship_select() -> void:
	menu_ui.hide()
	# Kiosk: every visitor starts on the first ship, not the previous
	# visitor's pick (GameSession outlives scene changes)
	GameSession.select_ship(0)
	ship_select.open()

func _on_ship_launch_requested(index: int) -> void:
	# A real run (never a demo)
	GameSession.demo_mode = false
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
