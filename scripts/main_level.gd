# level.gd
extends Node2D

# Node references
@onready var player: CharacterBody2D = $Player
@onready var spawn_manager: Node2D = $SpawnManager
@onready var background_music = $BackgroundMusic
@onready var atmosphere_manager = $AtmosphereManager
@onready var countdown_label: Label = $UI/CountdownLabel
@onready var height_label: Label = $UI/HeightDisplay/HeightLabel
@onready var health_label: Label = $UI/StatsDisplay/StatsContainer/HealthLabel
@onready var energy_label: Label = $UI/StatsDisplay/StatsContainer/EnergyLabel
@onready var game_over_screen: Control = $UI/GameOverScreen

# Game States
enum GameState {COUNTDOWN, PLAYING, PAUSED, GAME_OVER}
var current_state: GameState = GameState.COUNTDOWN

# Height tracking
var height_score: float = 0.0
@export var base_player_speed: float = 100.0
var scroll_speed: float = base_player_speed

# Player stats
var max_health: float = 100.0
var current_health: float = max_health
var max_energy: float = 100.0
var current_energy: float = max_energy
var energy_decay_rate: float = 5.0  # Energy lost per second

# Countdown
var countdown_time: float = 3.0
var current_countdown: float = 0.0

func _ready() -> void:
	#Start background music
	if background_music:
		background_music.play()
	else:
		print("Warning: background_music node not found")
	# Initialize game
	current_countdown = countdown_time
	update_countdown_display()
	player.disable_movement()

	# Initialize UI
	if not height_label:
		push_error("Height label not found!")
		return

	# Connect signals from collectibles and obstacles
	connect_game_objects()
	$UI/GameOverScreen.retry_pressed.connect(_on_game_over_retry)
	$UI/GameOverScreen.main_menu_pressed.connect(_on_game_over_main_menu)

	update_all_displays()

func connect_game_objects() -> void:
	# We'll connect signals from spawn manager
	if spawn_manager:
		spawn_manager.connect("object_spawned", _on_object_spawned)

func _on_object_spawned(game_object: Node2D) -> void:
	# Connect signals from newly spawned objects if they aren't already connected
	if game_object.has_signal("object_collected") and not game_object.is_connected("object_collected", _on_object_collected):
		game_object.connect("object_collected", _on_object_collected.bind(game_object))
	if game_object.has_signal("object_hit") and not game_object.is_connected("object_hit", _on_object_hit):
		game_object.connect("object_hit", _on_object_hit.bind(game_object))

func _process(delta: float) -> void:
	match current_state:
		GameState.COUNTDOWN:
			process_countdown(delta)
		GameState.PLAYING:
			process_game(delta)
		GameState.GAME_OVER:
			pass

func process_countdown(delta: float) -> void:
	current_countdown -= delta
	update_countdown_display()

	if current_countdown <= 0:
		start_game()

func process_game(delta: float) -> void:
	# Update height score
	height_score += scroll_speed * delta

	# Update energy (decrease over time)
	#update_energy(-energy_decay_rate * delta)

	# Check if out of energy or health
	if current_energy <= 0 or current_health <= 0:
		game_over()

	# Update displays
	update_all_displays()

	# Increase scroll speed gradually based on height
	scroll_speed = base_player_speed + (height_score * 0.01)

	# Update spawn difficulty based on height
	var current_height: int = int(height_score)
	update_spawn_difficulty(current_height)

func update_all_displays() -> void:
	update_height_display()
	update_health_display()
	update_energy_display()

func update_height_display() -> void:
	if not height_label:
		return
	var height_in_meters: int = int(height_score)
	height_label.text = "Height: %d m" % height_in_meters

func update_health_display() -> void:
	if not health_label:
		return
	health_label.text = "Health: %d%%" % int(current_health)

func update_energy_display() -> void:
	if not energy_label:
		return
	energy_label.text = "Energy: %d%%" % int(current_energy)

func update_health(amount: float) -> void:
	current_health = clamp(current_health + amount, 0, max_health)
	update_health_display()

func update_energy(amount: float) -> void:
	current_energy = clamp(current_energy + amount, 0, max_energy)
	update_energy_display()

func _on_object_collected(object: Node2D) -> void:
	if object is EnergyCollectible:
		update_energy(object.energy_value)

func _on_object_hit(object: Node2D) -> void:
	if object is Obstacle:
		if not player.is_blinking:
			update_health(-object.damage)
			player.start_blink()  # Start the blink effect)

func update_countdown_display() -> void:
	var countdown_text: String = ""
	if current_countdown > 0:
		var count: int = ceil(current_countdown)
		match count:
			3:
				countdown_text = "3"
			2:
				countdown_text = "2"
			1:
				countdown_text = "1"
	else:
		countdown_text = "LAUNCH!"

	countdown_label.text = countdown_text

func start_game() -> void:
	countdown_label.visible = false
	current_state = GameState.PLAYING
	player.enable_movement()  # Enable player movement
	spawn_manager.start_spawning()  # Start spawning objects

	# Start launch pad animation
	if $LaunchPad:
		$LaunchPad.start_launch()

func game_over() -> void:
	current_state = GameState.GAME_OVER
	player.disable_movement()
	spawn_manager.stop_spawning()
	
	# Show game over screen with final height score
	if game_over_screen:
		game_over_screen.show()
		game_over_screen.set_final_height(height_score)

func update_spawn_difficulty(height: int) -> void:
	# Update spawn manager parameters based on height
	var new_zone: String
	if height < 3000:  # Ground level
		new_zone = "ground"
	elif height < 10000:  # Atmosphere
		new_zone = "atmosphere"
	elif height < 30000:  # Upper atmosphere
		new_zone = "upper_atmosphere"
	else:  # Space
		new_zone = "space"

	spawn_manager.set_spawn_zone(new_zone)
	atmosphere_manager.set_zone(new_zone)

func _on_game_over_retry() -> void:
	# Reload the current scene
	get_tree().reload_current_scene()

func _on_game_over_main_menu() -> void:
	# Transition to main menu scene
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
