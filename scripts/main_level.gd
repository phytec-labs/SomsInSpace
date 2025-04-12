# level.gd
extends Node2D

# Node references
@onready var player: CharacterBody2D = $Player
@onready var spawn_manager: Node2D = $SpawnManager
@onready var background_music = $BackgroundMusic
@onready var atmosphere_manager = $AtmosphereManager
@onready var cloud_manager: Node2D = $CloudManager
@onready var countdown_label: Label = $UI/CountdownLabel
@onready var game_over_screen: Control = $UI/GameOverScreen
@onready var game_hud = $UI/GameHUDUi

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
var points: int = 0  # New variable to track points

# Countdown
var countdown_time: float = 3.0
var current_countdown: float = 0.0

# Zone tracking
var current_zone: String = "ground"

# Weapon upgrade variables
@export var weapon_upgrade_scene: PackedScene
var upgrade_spawned: bool = false
var message_label: Label

func _ready() -> void:
	print("Main Level Connected joypads: ", Input.get_connected_joypads())
	add_to_group("level")

	#Start background music
	if background_music:
		background_music.play()
	else:
		print("Warning: background_music node not found")

	# Initialize game
	current_countdown = countdown_time
	update_countdown_display()
	player.disable_movement()

	# Connect signals from collectibles and obstacles
	connect_game_objects()
	$UI/GameOverScreen.retry_pressed.connect(_on_game_over_retry)
	$UI/GameOverScreen.main_menu_pressed.connect(_on_game_over_main_menu)

	# Add GameHud to the "hud" group so it can be found by collectibles
	if game_hud:
		game_hud.add_to_group("hud")

	# Create a message label for displaying upgrade messages
	message_label = Label.new()
	message_label.add_theme_font_override("font", preload("res://fonts/m5x7.ttf"))
	message_label.add_theme_font_size_override("font_size", 40)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.visible = false
	message_label.anchors_preset = Control.PRESET_CENTER
	message_label.size = Vector2(600, 100)
	message_label.position = Vector2(-300, -50)  # Center it

	# Add outline effect
	message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	message_label.add_theme_constant_override("outline_size", 3)

	# Add to UI layer
	$UI.add_child(message_label)

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

	cloud_manager.update_height(height_score)

	# Check if out of health
	if current_health <= 0:
		game_over()

	# Update displays
	update_all_displays()

	# Update spawn difficulty based on height
	var current_height: int = int(height_score)
	update_spawn_difficulty(current_height)

func update_all_displays() -> void:
	game_hud.update_height(height_score)
	game_hud.update_health(current_health)
	game_hud.update_points(points)

func update_height_display() -> void:
	game_hud.update_height(height_score)

func update_health_display() -> void:
	game_hud.update_health(current_health)

func update_points_display() -> void:
	game_hud.update_points(points)

func update_health(amount: float) -> void:
	current_health = clamp(current_health + amount, 0, max_health)
	update_health_display()

func update_points(amount: int) -> void:  # New function to update points
	points += amount
	update_points_display()

func _on_object_collected(object: Node2D) -> void:
	if object is EnergyCollectible:
		# Add points based on the collectible's value
		update_points(object.points)  # Use the points property from GameObject class

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
	player.enable_movement()
	spawn_manager.start_spawning()
	cloud_manager.start_spawning()

	# Start launch pad animation
	if $LaunchPad:
		$LaunchPad.start_launch()

func game_over() -> void:
	current_state = GameState.GAME_OVER

	# Create player explosion before hiding the player
	create_player_explosion()

	# Call the player's die function
	player.die()

	# Stop game systems
	spawn_manager.stop_spawning()
	cloud_manager.stop_spawning()

	# Show game over screen after a short delay to see explosion
	await get_tree().create_timer(1.0).timeout

	if game_over_screen:
		game_over_screen.show()
		game_over_screen.set_final_height(height_score)
		game_over_screen.set_final_score(points)

func create_player_explosion() -> void:
	# Define the explosion scene - same as enemies use
	var explosion_scene = preload("res://scenes/effects/explosion.tscn")

	# Create the explosion
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		add_child(explosion)
		explosion.global_position = player.global_position

		# Make explosion bigger for player (type 2 = LARGE)
		explosion.set_explosion_type(2)
		explosion.start()

func update_spawn_difficulty(height: int) -> void:
	# Use a dictionary for zone thresholds
	var zone_thresholds = {
		"ground": 0,
		"atmosphere": 3000,
		"upper_atmosphere": 10000,
		"space": 30000
	}

	# Check if we should spawn the weapon upgrade at the atmosphere level
	if current_zone == "atmosphere" and not upgrade_spawned:
		spawn_weapon_upgrade()

	# Determine new zone
	var new_zone = "ground"
	for zone in zone_thresholds:
		if height >= zone_thresholds[zone]:
			new_zone = zone

	# Only update if the zone has changed
	if new_zone != current_zone:
		current_zone = new_zone

		# Update all managers at once
		spawn_manager.set_spawn_zone(new_zone)
		atmosphere_manager.set_zone(new_zone)
		cloud_manager.set_zone(new_zone)

func _on_game_over_retry() -> void:
	# Reload the current scene
	get_tree().reload_current_scene()

func _on_game_over_main_menu() -> void:
	# Transition to main menu scene
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func spawn_weapon_upgrade() -> void:
	if not weapon_upgrade_scene or upgrade_spawned:
		return

	upgrade_spawned = true

	# Create the upgrade collectible
	var upgrade = weapon_upgrade_scene.instantiate()
	add_child(upgrade)

	# Calculate spawn position - centered horizontally and just above screen
	var viewport_rect = get_viewport_rect()
	var spawn_x = viewport_rect.size.x / 2
	var spawn_y = -100

	# Initialize the collectible
	upgrade.initialize(Vector2(spawn_x, spawn_y))

	# Show message to notify player
	show_message("Weapon Upgrade Available!")

func show_message(text: String, duration: float = 3.0) -> void:
	if not message_label:
		return

	# Set message text
	message_label.text = text
	message_label.visible = true

	# Animate in
	message_label.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(message_label, "modulate", Color(1, 1, 1, 1), 0.5)
	tween.tween_interval(duration - 1.0)  # Wait
	tween.tween_property(message_label, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_callback(func(): message_label.visible = false)
