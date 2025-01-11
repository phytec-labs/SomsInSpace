# level.gd
extends Node2D

# Node references
@onready var player: CharacterBody2D = $Player
@onready var spawn_manager: Node2D = $SpawnManager
@onready var countdown_label: Label = $UI/CountdownLabel
@onready var height_label: Label = $UI/HeightDisplay/HeightLabel
@onready var health_label: Label = $UI/StatsDisplay/StatsContainer/HealthLabel
@onready var energy_label: Label = $UI/StatsDisplay/StatsContainer/EnergyLabel

# Game States
enum GameState {COUNTDOWN, PLAYING, PAUSED, GAME_OVER}
var current_state: GameState = GameState.COUNTDOWN

# Height tracking
var height_score: float = 0.0
var scroll_speed: float = 200.0

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

	update_all_displays()

func connect_game_objects() -> void:
	# We'll connect signals from spawn manager
	if spawn_manager:
		spawn_manager.connect("object_spawned", _on_object_spawned)

func _on_object_spawned(game_object: Node2D) -> void:
	# Connect signals from newly spawned objects
	if game_object.has_signal("object_collected"):
		game_object.connect("object_collected", _on_object_collected.bind(game_object))
	if game_object.has_signal("object_hit"):
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
	update_energy(-energy_decay_rate * delta)

	# Check if out of energy or health
	if current_energy <= 0 or current_health <= 0:
		game_over()

	# Update displays
	update_all_displays()

	# Increase scroll speed gradually based on height
	scroll_speed = 200.0 + (height_score * 0.01)

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
		update_health(-object.damage)

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
	# Show game over UI with final height, etc.

func update_spawn_difficulty(height: int) -> void:
	# Update spawn manager parameters based on height
	var new_zone: String
	if height < 1000:  # Ground level
		new_zone = "ground"
	elif height < 20000:  # Atmosphere
		new_zone = "atmosphere"
	elif height < 100000:  # Upper atmosphere
		new_zone = "upper_atmosphere"
	else:  # Space
		new_zone = "space"

	spawn_manager.set_spawn_zone(new_zone)
	$AtmosphereManager.set_zone(new_zone)
