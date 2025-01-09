# level.gd
extends Node2D

# Node references
@onready var player: CharacterBody2D = $Player
@onready var spawn_manager: Node2D = $SpawnManager
@onready var countdown_label: Label = $UI/CountdownLabel

# Game States
enum GameState {COUNTDOWN, PLAYING, PAUSED, GAME_OVER}
var current_state: GameState = GameState.COUNTDOWN

# Height tracking
var height_score: float = 0.0
var scroll_speed: float = 200.0

# Countdown
var countdown_time: float = 3.0
var current_countdown: float = 0.0

func _ready() -> void:
	# Initialize game
	current_countdown = countdown_time
	update_countdown_display()
	player.disable_movement()  # Disable player movement during countdown

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

	# Increase scroll speed gradually based on height
	scroll_speed = 200.0 + (height_score * 0.01)

	# Update spawn difficulty based on height
	var current_height: int = int(height_score)
	update_spawn_difficulty(current_height)

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

func game_over() -> void:
	current_state = GameState.GAME_OVER
	player.disable_movement()
	spawn_manager.stop_spawning()
	# Show game over UI, high score, etc.

func update_spawn_difficulty(height: int) -> void:
	# Update spawn manager parameters based on height
	if height < 1000:  # Ground level
		spawn_manager.set_spawn_zone("ground")
	elif height < 20000:  # Atmosphere
		spawn_manager.set_spawn_zone("atmosphere")
	elif height < 100000:  # Upper atmosphere
		spawn_manager.set_spawn_zone("upper_atmosphere")
	else:  # Space
		spawn_manager.set_spawn_zone("space")
