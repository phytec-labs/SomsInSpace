# level.gd
extends Node2D

# Preloaded (not referenced by class_name) so this works even before the
# editor has rebuilt the global class cache.
const GameConfigScript := preload("res://scripts/data/game_config.gd")
const ZoneDefinitionScript := preload("res://scripts/data/zone_definition.gd")
const EXPLOSION_SCENE := preload("res://scenes/effects/explosion.tscn")

## All zone / pacing tuning (see res://data/game_config.tres)
@export var config: GameConfigScript

# Node references
@onready var player: CharacterBody2D = $Player
@onready var spawn_manager: Node2D = $SpawnManager
@onready var background_music = $BackgroundMusic
@onready var atmosphere_manager = $AtmosphereManager
@onready var cloud_manager: Node2D = $CloudManager
@onready var countdown_label: Label = $UI/CountdownLabel
@onready var game_over_screen: Control = $UI/GameOverScreen
@onready var game_hud = $UI/GameHUDUi
@onready var pause_menu: Control = $UI/PauseMenu

# Game States
enum GameState {COUNTDOWN, PLAYING, PAUSED, GAME_OVER, VICTORY}
var current_state: GameState = GameState.COUNTDOWN

# Height tracking
var height_score: float = 0.0
var scroll_speed: float = 100.0  # From config.scroll_speed

# Player stats
var max_health: float = 100.0
var current_health: float = max_health
var points: int = 0  # New variable to track points

# Countdown
var countdown_time: float = 3.0  # From config.countdown_time
var current_countdown: float = 0.0

# Zone tracking (current_zone is the zone id, e.g. "ground")
var current_zone: String = ""
var current_zone_def: ZoneDefinitionScript

# Boss fight (zone with a boss_scene)
const VICTORY_BONUS_PER_HEALTH: int = 10
const VICTORY_SCREEN_DELAY: float = 2.5
var boss: Node2D = null
var victory_bonus: int = 0

# Weapon upgrade variables
@export var weapon_upgrade_scene: PackedScene
var upgrade_spawned: bool = false
@onready var message_label = $UI/GameHUDUi/MessageControl/MarginContainer/Label

func _ready() -> void:
	print("Main Level Connected joypads: ", Input.get_connected_joypads())
	add_to_group("level")

	# Apply config and hand it to the systems that need it
	if not config:
		push_error("MainLevel: no GameConfig assigned")
		config = GameConfigScript.new()
	scroll_speed = config.scroll_speed
	countdown_time = config.countdown_time
	game_hud.configure(config)
	spawn_manager.configure(config)
	_update_zone(0)

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

	# Pause menu / HUD pause button
	pause_menu.resume_pressed.connect(resume_game)
	pause_menu.main_menu_pressed.connect(_on_pause_main_menu)
	game_hud.pause_requested.connect(pause_game)
	game_hud.set_pause_button_visible(false)

	# Add GameHud to the "hud" group so it can be found by collectibles
	if game_hud:
		game_hud.add_to_group("hud")

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
		GameState.PAUSED:
			pass  # Tree is paused; _process doesn't run in this state
		GameState.GAME_OVER, GameState.VICTORY:
			pass

func _unhandled_input(event: InputEvent) -> void:
	# Escape pauses during play. While paused this node doesn't process
	# input; the pause menu (PROCESS_MODE_ALWAYS) handles ui_cancel to resume.
	if event.is_action_pressed("ui_cancel") and current_state == GameState.PLAYING:
		get_viewport().set_input_as_handled()
		pause_game()

func _exit_tree() -> void:
	# Never leave the tree paused when this level goes away (scene change,
	# reload, quit), so the next scene isn't born paused.
	get_tree().paused = false

func pause_game() -> void:
	# Only pause during active play (not countdown or game over)
	if current_state != GameState.PLAYING:
		return
	current_state = GameState.PAUSED
	game_hud.set_pause_button_visible(false)
	get_tree().paused = true
	pause_menu.show()

func resume_game() -> void:
	if current_state != GameState.PAUSED:
		return
	pause_menu.hide()
	current_state = GameState.PLAYING
	# Clear any touch/fire state the player latched before the pause; the
	# matching release events were delivered while the player was paused.
	player.reset_input_state()
	get_tree().paused = false
	game_hud.set_pause_button_visible(true)

func _on_pause_main_menu() -> void:
	if current_state != GameState.PAUSED:
		return
	# Unpause BEFORE changing scene so the main menu isn't born paused
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func process_countdown(delta: float) -> void:
	current_countdown -= delta
	update_countdown_display()

	if current_countdown <= 0:
		start_game()

func process_game(delta: float) -> void:
	# Update height score (frozen in e.g. the boss zone; scrolling visuals
	# keep going)
	if not (current_zone_def and current_zone_def.freezes_height):
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
	# No damage once the run has ended (stray shots after victory / game over)
	if amount < 0.0 and current_state != GameState.PLAYING:
		return
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
	# No damage once the run has ended (e.g. stray boss shots after victory)
	if current_state != GameState.PLAYING:
		return
	if object is Obstacle:
		if not player.is_blinking and not player.is_dead:
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
	game_hud.set_pause_button_visible(true)
	player.enable_movement()
	spawn_manager.start_spawning()
	cloud_manager.start_spawning()

	# Start launch pad animation
	if $LaunchPad:
		$LaunchPad.start_launch()

func game_over() -> void:
	current_state = GameState.GAME_OVER
	game_hud.set_pause_button_visible(false)

	# Create player explosion before hiding the player
	create_player_explosion()

	# Call the player's die function
	player.die()

	# Stop game systems
	spawn_manager.stop_spawning()
	cloud_manager.stop_spawning()
	# A live boss stops attacking (it keeps hovering behind the results)
	if is_instance_valid(boss) and boss.has_method("stand_down"):
		boss.stand_down()

	# Show game over screen after a short delay to see explosion
	await get_tree().create_timer(1.0).timeout

	# The level may have left the tree (scene change) during the wait
	if not is_inside_tree():
		return
	game_hud.hide_boss_bar()
	if game_over_screen:
		# SET VALUES FIRST - before showing the screen
		game_over_screen.set_final_height(height_score)
		game_over_screen.set_final_score(points)
		# THEN show the screen
		game_over_screen.show()

func create_player_explosion() -> void:
	# Same (pooled) explosion scene the enemies use
	var explosion = ObjectPool.acquire(EXPLOSION_SCENE, self)
	explosion.global_position = player.global_position

	# Make explosion bigger for player (type 2 = LARGE)
	explosion.set_explosion_type(2)
	explosion.start()

func update_spawn_difficulty(height: int) -> void:
	# Spawn the weapon upgrade (once per run) in the zone that asks for it
	if current_zone_def and current_zone_def.spawns_weapon_upgrade and not upgrade_spawned:
		spawn_weapon_upgrade()

	_update_zone(height)

# Switch every manager to the zone for `height` (no-op if unchanged)
func _update_zone(height: float) -> void:
	var zone: ZoneDefinitionScript = config.get_zone_for_height(height)
	if zone == null or zone == current_zone_def:
		return
	current_zone_def = zone
	current_zone = String(zone.id)

	# Height-freezing zones (the boss zone) pin the height at their start so
	# the final height / HUD marker land exactly on the zone boundary
	if zone.freezes_height:
		height_score = zone.start_height

	# Update all managers at once
	spawn_manager.set_spawn_zone(zone)
	atmosphere_manager.set_zone_appearance(current_zone, zone.background_color, zone.star_visibility)
	cloud_manager.set_zone(current_zone)
	cloud_manager.set_clouds_enabled(zone.has_clouds)

	if zone.boss_scene:
		_start_boss_fight(zone)

# Boss zone entered: spawn the boss and hook its signals up to the HUD
func _start_boss_fight(zone: ZoneDefinitionScript) -> void:
	if boss != null:
		return
	show_message("WARNING: MOTHERSHIP")
	if not spawn_manager.has_method("spawn_boss"):
		push_error("MainLevel: SpawnManager has no spawn_boss(); boss not spawned")
		return
	boss = spawn_manager.spawn_boss(zone.boss_scene)
	if boss == null:
		push_error("MainLevel: spawn_boss() returned null for zone " + String(zone.id))
		return
	_connect_boss(boss)

# Wire the boss's signals (BossAlien: fight_started, health_changed, defeated)
func _connect_boss(new_boss: Node2D) -> void:
	boss = new_boss
	# (connected by name: `boss` is typed Node2D, not BossAlien)
	if boss.has_signal("fight_started"):
		boss.connect("fight_started", _on_boss_fight_started)
	if boss.has_signal("health_changed"):
		boss.connect("health_changed", game_hud.update_boss_health)
	if boss.has_signal("defeated"):
		boss.connect("defeated", _on_boss_defeated, CONNECT_ONE_SHOT)

func _on_boss_fight_started() -> void:
	# The entrance can finish after the run already ended
	if current_state != GameState.PLAYING and current_state != GameState.PAUSED:
		return
	var boss_name := "Mothership"
	if is_instance_valid(boss) and "boss_name" in boss and not String(boss.get("boss_name")).is_empty():
		boss_name = String(boss.get("boss_name"))
	game_hud.show_boss_bar(boss_name)

func _on_boss_defeated() -> void:
	# Only a live run can be won (not after the player already died)
	if current_state != GameState.PLAYING:
		return
	current_state = GameState.VICTORY
	game_hud.set_pause_button_visible(false)

	# Stop the run; the ship stays on screen (no explosion)
	spawn_manager.stop_spawning()
	cloud_manager.stop_spawning()
	player.disable_movement()
	player.reset_input_state()

	game_hud.hide_boss_bar()
	show_message("ORBIT REACHED!")

	victory_bonus = int(current_health) * VICTORY_BONUS_PER_HEALTH
	update_points(victory_bonus)

	# Let the boss death sequence play out before the results screen. The
	# timeout is connected to a method (rather than awaited) so nothing
	# resumes if the level is freed during the wait.
	get_tree().create_timer(VICTORY_SCREEN_DELAY).timeout.connect(_show_victory_screen)

func _show_victory_screen() -> void:
	if not is_inside_tree() or current_state != GameState.VICTORY:
		return
	if game_over_screen:
		game_over_screen.set_victory(true, victory_bonus)
		game_over_screen.set_final_height(height_score)
		game_over_screen.set_final_score(points)
		game_over_screen.show()

func _on_game_over_retry() -> void:
	# Only reachable from the game over screen, never while paused
	if not _is_run_over():
		return
	get_tree().paused = false
	# Reload the current scene
	get_tree().reload_current_scene()

func _on_game_over_main_menu() -> void:
	if not _is_run_over():
		return
	get_tree().paused = false
	# Transition to main menu scene
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# True once the run has ended (game over or victory)
func _is_run_over() -> bool:
	return current_state == GameState.GAME_OVER or current_state == GameState.VICTORY

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
