# level.gd
extends Node2D

# Game States
enum GameState {COUNTDOWN, PLAYING, PAUSED, GAME_OVER}
var current_state = GameState.COUNTDOWN

# Height tracking
var height_score: float = 0
var scroll_speed: float = 200.0

# Countdown
var countdown_time: float = 3.0
var current_countdown: float = 0.0

func _ready():
	# Initialize game
	current_countdown = countdown_time
	update_countdown_display()
	$Player.disable_movement()  # Disable player movement during countdown

func _process(delta):
	match current_state:
		GameState.COUNTDOWN:
			process_countdown(delta)
		GameState.PLAYING:
			process_game(delta)
			height_score += scroll_speed * delta
		GameState.GAME_OVER:
			pass

func process_countdown(delta):
	current_countdown -= delta
	update_countdown_display()
	
	if current_countdown <= 0:
		start_game()

func update_countdown_display():
	var countdown_text = ""
	if current_countdown > 0:
		var count = ceil(current_countdown)
		match count:
			3:
				countdown_text = "3"
			2:
				countdown_text = "2"
			1:
				countdown_text = "1"
	else:
		countdown_text = "LAUNCH!"
	
	$UI/CountdownLabel.text = countdown_text

func start_game():
	$UI/CountdownLabel.visible = false
	current_state = GameState.PLAYING
	$Player.enable_movement()  # Enable player movement
	$SpawnManager.start_spawning()  # Start spawning objects

func game_over():
	current_state = GameState.GAME_OVER
	$Player.disable_movement()
	$SpawnManager.stop_spawning()
	# Show game over UI, high score, etc.
