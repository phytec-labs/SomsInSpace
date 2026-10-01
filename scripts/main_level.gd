# level.gd
extends Node2D

# Preloaded (not referenced by class_name) so this works even before the
# editor has rebuilt the global class cache.
const GameConfigScript := preload("res://scripts/data/game_config.gd")
const ZoneDefinitionScript := preload("res://scripts/data/zone_definition.gd")
const EXPLOSION_SCENE := preload("res://scenes/effects/explosion.tscn")
const DOCKING_STATION_SCENE := preload("res://scenes/effects/docking_station.tscn")
const SCORE_POPUP_SCENE := preload("res://scenes/effects/juice_score_popup.tscn")

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
@onready var game_camera: Camera2D = get_node_or_null("GameCamera")

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
# Victory bonus per percent of max health left (full health = +1000 for
# every ship, whatever its max_health)
const VICTORY_BONUS_PER_HEALTH_PERCENT: int = 10
var boss: Node2D = null
var victory_bonus: int = 0
# Victory docking sequence (timings live on docking_station.gd)
var docking_station: Node2D = null

# --- Juice: combo multiplier, grazes, score popups, screen shake ---
#
# KILL POINTS / COMBO: obstacle.gd (and boss_alien.gd, via the same
# Obstacle._award_kill_points()) calls level.award_kill_points(abs(points),
# self) before emitting `destroyed`. That awards the full multiplied amount
# and marks the kill with the obstacle's spawn_count, so the `destroyed` hook
# (_on_enemy_destroyed) skips it. The hook still handles what never goes
# through award_kill_points: mine detonations (shake, no points) and rams (no
# points); any other destroyed obstacle falls back to "base already awarded"
# and only gets the combo extra.
## Seconds after a kill in which the next kill raises the combo
@export var combo_window: float = 1.5
## Highest combo multiplier
@export var max_combo: int = 4
## Points per near miss (enemy shot through the player's GrazeArea)
@export var graze_points: int = 5
const COMBO_COLORS: Array[Color] = [
	Color(1, 1, 1),        # x1 white
	Color(1, 0.95, 0.25),  # x2 yellow
	Color(1, 0.6, 0.15),   # x3 orange
	Color(1, 0.2, 0.15),   # x4 red
]
const GRAZE_COLOR := Color(0.35, 1, 1)
const GRAZE_POPUP_SCALE := 0.7
# Screen shake presets: trauma strength (0..1) and duration (s). Kill shakes
# scale from SHAKE_KILL_MIN to SHAKE_KILL_MAX with the kill's points
# (SHAKE_KILL_POINTS_FULL points or more = max).
const SHAKE_KILL_MIN := 0.3
const SHAKE_KILL_MAX := 0.5
const SHAKE_KILL_POINTS_FULL := 100.0
const SHAKE_KILL_TIME := 0.15
const SHAKE_MEDIUM := 0.6        # Mine detonation, asteroid split
const SHAKE_MEDIUM_TIME := 0.3
const SHAKE_LARGE := 0.85        # Player hit, boss phase change
const SHAKE_LARGE_TIME := 0.4
const SHAKE_CLAMP := 0.75        # Docking clamps close
const SHAKE_CLAMP_TIME := 0.35
const SHAKE_GRAZE := 0.25
const SHAKE_GRAZE_TIME := 0.1
const SHAKE_BOMB := 1.0          # Screen-clear bomb
const SHAKE_BOMB_TIME := 0.6
const SHAKE_SHIELD := 0.3        # Hit absorbed by the shield
const SHAKE_SHIELD_TIME := 0.12

# --- Pickups (health cell, shield bubble, screen-clear bomb) ---
# Values live in GameConfig (health_pickup_amount, shield_duration,
# shield_drain_factor, bomb_boss_damage); the SpawnManager rolls which
# pickup spawns (ZoneDefinition.pickup_weight_*).
const HEAL_COLOR := Color(0.35, 1, 0.45)
const SHIELD_COLOR := Color(0.4, 1, 1)
const BOMB_FLASH_TIME := 0.25
const BOMB_FLASH_ALPHA := 0.85
## Obstacles / shots count as "on screen" for the bomb within this margin (px)
const BOMB_SCREEN_MARGIN := 24.0
## Damage the bomb deals to every non-boss obstacle (always lethal; dealt
## through Obstacle.bomb_kill(), so asteroids don't split)
const BOMB_KILL_DAMAGE := 9999.0
## Boss phase changes (2 and 3) drop a health cell this far below the boss
const BOSS_DROP_OFFSET := Vector2(0, 130)
var _bomb_flash: ColorRect = null
var _bomb_flash_left: float = 0.0
# Observability (tests / tuning)
var bomb_count: int = 0
var last_bomb_kills: int = 0
var last_bomb_projectiles_cleared: int = 0
var boss_health_drops: int = 0
var health_healed_total: float = 0.0
var shield_ram_kills: int = 0

var combo: int = 1
var _combo_time_left: float = 0.0
# Observability (tests / tuning)
var kill_count: int = 0
var combo_bonus_total: int = 0
var graze_count: int = 0

# Weapon upgrade pickups: one per zone with spawns_weapon_upgrade, per run
@export var weapon_upgrade_scene: PackedScene
var weapon_upgrades_spawned := {}  # zone id (String) -> true once its pickup spawned
var _live_weapon_upgrades: Array = []  # Spawned pickups not yet collected

# HUD threat indicator (wave manager ramp level; -1 = not shown yet)
var wave_manager: Node = null
var _last_threat_level: int = -1
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
	_apply_selected_ship()
	spawn_manager.configure(config)
	wave_manager = spawn_manager.get("wave_manager")
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
		game_hud.update_weapon(player.weapon_tier)

	update_all_displays()

# Ship chosen on the ship select screen (GameSession autoload): player stats
# and sprite, health, HUD ship name
func _apply_selected_ship() -> void:
	var ship = GameSession.selected_ship
	if ship == null:
		return
	player.apply_ship(ship)
	max_health = ship.max_health
	current_health = max_health
	game_hud.set_max_health(max_health)
	game_hud.set_ship_name(ship.display_name)

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
	# Kills (popups / combo / shake): once per instance and level. Pooled
	# instances outlive a scene reload, so the meta holds this level's id.
	if game_object.has_signal("destroyed") \
			and game_object.get_meta("_juice_level_connected", 0) != get_instance_id():
		game_object.set_meta("_juice_level_connected", get_instance_id())
		game_object.connect("destroyed", _on_enemy_destroyed.bind(game_object))

func _process(delta: float) -> void:
	_update_bomb_flash(delta)
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

	_update_threat_display()
	_update_combo(delta)
	game_hud.update_shield(player.get_shield_fraction())

# Push the wave manager's ramp level to the HUD (only when it changes)
func _update_threat_display() -> void:
	if wave_manager == null:
		return
	var level: int = wave_manager.get_ramp_level()
	if level != _last_threat_level:
		_last_threat_level = level
		game_hud.update_threat(level)

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
	# Shield bubble: the hit is absorbed (no health loss, the combo survives,
	# no weapon tier loss); the shield flashes and keeps going
	if amount < 0.0 and player.is_shielded():
		_absorb_shield_hit()
		return
	current_health = clamp(current_health + amount, 0, max_health)
	update_health_display()

	# A damaging hit breaks the combo and shakes the screen hard
	if amount < 0.0:
		_reset_combo()
		shake(SHAKE_LARGE, SHAKE_LARGE_TIME)

	# Every damaging hit goes through here (obstacle contact via
	# _on_object_hit, enemy shots call update_health directly); continuous
	# drains use apply_drain() instead
	if amount < 0.0 and config.lose_weapon_tier_on_hit and current_health > 0:
		_drop_weapon_tier()

# Continuous damage from a hazard the player escapes by moving (e.g. the UFO
# tractor beam): call every frame it lasts with the per-second rate and the
# frame delta. Unlike update_health() hits it never costs a weapon tier
# (GameConfig.lose_weapon_tier_on_hit) and neither starts nor is blocked by
# the damage blink. Game over is detected by process_game() as usual.
func apply_drain(amount_per_second: float, delta: float) -> void:
	if current_state != GameState.PLAYING or amount_per_second <= 0.0 or delta <= 0.0:
		return
	# The shield only halves drains (the beam is escapable)
	if player.is_shielded():
		amount_per_second *= config.shield_drain_factor
	current_health = clampf(current_health - amount_per_second * delta, 0.0, max_health)
	update_health_display()

# Health cell: restore `amount` (clamped to max_health), green popup at the
# ship. Returns the health actually restored.
func heal(amount: float) -> float:
	if amount <= 0.0 or current_state != GameState.PLAYING:
		return 0.0
	var before := current_health
	current_health = clampf(current_health + amount, 0.0, max_health)
	update_health_display()
	var healed := current_health - before
	health_healed_total += healed
	var text := "+%d" % int(round(healed)) if healed > 0.0 else "MAX"
	spawn_score_popup(text, player.global_position + Vector2(0, -70), HEAL_COLOR)
	return healed

# A damaging hit met the shield (update_health): pop the ring, small shake
func _absorb_shield_hit() -> void:
	player.shield_absorb_hit()
	shake(SHAKE_SHIELD, SHAKE_SHIELD_TIME)

# Optional rule (GameConfig.lose_weapon_tier_on_hit): a hit costs one tier
func _drop_weapon_tier() -> void:
	if player.weapon_tier <= 1:
		return
	player.set_weapon_tier(player.weapon_tier - 1)
	game_hud.update_weapon(player.weapon_tier)
	show_message("Weapon damaged!")

func update_points(amount: int) -> void:  # New function to update points
	points += amount
	update_points_display()

# --- Kills, combo, grazes ---

# Entry point for kill points (see the KILL POINTS note at the top): awards
# `amount` x the combo multiplier, advances the combo, pops the score and
# shakes. Pass the killed obstacle as `source` (popup position, and it marks
# the kill so the `destroyed` hook doesn't count it again).
func award_kill_points(amount: int, source: Node2D = null) -> void:
	var at: Vector2 = player.global_position
	if is_instance_valid(source):
		at = source.global_position
		if "spawn_count" in source:
			source.set_meta("_kill_awarded_spawn", source.spawn_count)
	_register_kill(absi(amount), at, false)
	# Asteroid that splits into pieces (not when bombed or rammed)
	if is_instance_valid(source) and "size_level" in source and source.size_level > 1 \
			and not source.get("suppress_splits") and not source.get("is_being_collected"):
		shake(SHAKE_MEDIUM, SHAKE_MEDIUM_TIME)

# `destroyed` from any spawned obstacle (enemies, mines, asteroids, minions,
# blimp, boss). Tells kills from rams and mine detonations without touching
# obstacle.gd: a ram sets is_being_collected; a detonation bumps the mine's
# detonation_count.
func _on_enemy_destroyed(obstacle: Node2D) -> void:
	if not is_instance_valid(obstacle):
		return
	# Already handled by award_kill_points()
	if "spawn_count" in obstacle and obstacle.get_meta("_kill_awarded_spawn", -1) == obstacle.spawn_count:
		return
	# Mine detonation: medium shake, no kill
	if "detonation_count" in obstacle:
		var detonations: int = obstacle.detonation_count
		if detonations != obstacle.get_meta("_juice_detonations", 0):
			obstacle.set_meta("_juice_detonations", detonations)
			shake(SHAKE_MEDIUM, SHAKE_MEDIUM_TIME)
			return
	# Rammed by the player: no points (the hit itself shakes)
	if "is_being_collected" in obstacle and obstacle.is_being_collected:
		return
	var base_points: int = absi(int(obstacle.get("points")))
	_register_kill(base_points, obstacle.global_position, true)
	# Asteroid that splits into pieces
	if "size_level" in obstacle and obstacle.size_level > 1:
		shake(SHAKE_MEDIUM, SHAKE_MEDIUM_TIME)

# One kill worth `base_points`. The combo only runs while PLAYING (x1 after
# the run ended, e.g. the boss's final explosion). `base_already_awarded`:
# obstacle.gd already added base_points, so only the combo extra is added.
func _register_kill(base_points: int, at: Vector2, base_already_awarded: bool) -> void:
	kill_count += 1
	var multiplier := 1
	if current_state == GameState.PLAYING:
		combo = mini(combo + 1, maxi(max_combo, 1)) if _combo_time_left > 0.0 else 1
		_combo_time_left = combo_window
		multiplier = combo
		game_hud.update_combo(combo, 1.0, _combo_color(combo))

	var total := base_points * multiplier
	if base_already_awarded:
		var bonus := total - base_points
		if bonus > 0:
			combo_bonus_total += bonus
			update_points(bonus)
	else:
		update_points(total)

	if base_points > 0:
		spawn_score_popup("+%d" % total, at, _combo_color(multiplier))
	var t := clampf(float(base_points) / SHAKE_KILL_POINTS_FULL, 0.0, 1.0)
	shake(lerpf(SHAKE_KILL_MIN, SHAKE_KILL_MAX, t), SHAKE_KILL_TIME)

func _combo_color(value: int) -> Color:
	return COMBO_COLORS[clampi(value, 1, COMBO_COLORS.size()) - 1]

# Combo window countdown (process_game, so it freezes while paused)
func _update_combo(delta: float) -> void:
	if _combo_time_left <= 0.0:
		return
	_combo_time_left -= delta
	if _combo_time_left <= 0.0:
		_reset_combo()
	elif combo > 1:
		game_hud.update_combo(combo, _combo_time_left / combo_window, _combo_color(combo))

func _reset_combo() -> void:
	combo = 1
	_combo_time_left = 0.0
	game_hud.update_combo(1, 0.0)

# Near miss (enemy_projectile.gd, once per shot): points, cyan popup, tiny shake
func award_graze(at: Vector2) -> void:
	if current_state != GameState.PLAYING:
		return
	graze_count += 1
	update_points(graze_points)
	spawn_score_popup("GRAZE +%d" % graze_points, at, GRAZE_COLOR, GRAZE_POPUP_SCALE)
	shake(SHAKE_GRAZE, SHAKE_GRAZE_TIME)

# Pooled floating text (self-releases after its lifetime)
func spawn_score_popup(text: String, at: Vector2, color: Color, size_scale: float = 1.0) -> void:
	var popup = ObjectPool.acquire(SCORE_POPUP_SCENE, self)
	if popup:
		popup.popup(text, at, color, size_scale)

# Screen shake on the GameCamera (the UI CanvasLayer never shakes)
func shake(strength: float, duration: float) -> void:
	if game_camera and game_camera.has_method("shake"):
		game_camera.shake(strength, duration)

func _on_object_collected(object: Node2D) -> void:
	if object is EnergyCollectible:
		# Add points based on the collectible's value
		update_points(object.points)  # Use the points property from GameObject class
		if object.get_pickup_type() == &"weapon":
			_on_weapon_upgrade_collected(object)
		_apply_pickup(object.get_pickup_type())

# A weapon upgrade was collected: if it is the current zone's pickup, tell the
# wave manager, which schedules the zone's mini-boss (the blimp in the
# atmosphere) ZoneDefinition.miniboss_delay_after_upgrade later
func _on_weapon_upgrade_collected(upgrade: Node) -> void:
	if current_state != GameState.PLAYING or wave_manager == null:
		return
	if String(upgrade.get_meta(&"zone_id", "")) != current_zone:
		return  # Collected after its zone ended
	if wave_manager.has_method("notify_weapon_upgrade_collected"):
		wave_manager.notify_weapon_upgrade_collected()

# Effect of a collected pickup (points are awarded by the caller). Only
# during play (e.g. a pickup drifting into the docking ship does nothing).
func _apply_pickup(kind: StringName) -> void:
	if current_state != GameState.PLAYING:
		return
	match kind:
		&"health":
			heal(config.health_pickup_amount)
		&"shield":
			player.activate_shield(config.shield_duration)
			spawn_score_popup("SHIELD", player.global_position + Vector2(0, -70), SHIELD_COLOR)
		&"bomb":
			detonate_bomb()

# --- Screen-clear bomb ---

# Flash + big shake; every active non-boss obstacle on screen is destroyed
# through Obstacle.bomb_kill() (normal kill points, combo rises as usual,
# blimp loot drops, but asteroids do NOT split), the boss takes
# GameConfig.bomb_boss_damage, and enemy projectiles on screen are removed.
func detonate_bomb() -> void:
	if current_state != GameState.PLAYING:
		return
	bomb_count += 1
	show_message("BOMB!", 1.5)
	shake(SHAKE_BOMB, SHAKE_BOMB_TIME)
	_start_bomb_flash()

	var screen := get_viewport_rect().grow(BOMB_SCREEN_MARGIN)
	var kills_before := kill_count
	# Snapshot first: kills return obstacles to the pool while we iterate
	var targets: Array = []
	for object in spawn_manager.get_live_objects():
		if is_instance_valid(object) and object is Obstacle and object.is_active \
				and screen.has_point(object.global_position):
			targets.append(object)
	for object in targets:
		if not is_instance_valid(object) or not object.is_active:
			continue
		if object == boss:
			object.take_damage(config.bomb_boss_damage)
		elif object.has_method("bomb_kill"):
			object.bomb_kill(BOMB_KILL_DAMAGE)
		else:
			object.take_damage(BOMB_KILL_DAMAGE)
	last_bomb_kills = kill_count - kills_before

	last_bomb_projectiles_cleared = 0
	for shot in get_tree().get_nodes_in_group(&"enemy_projectile"):
		if shot.get("is_active") and screen.has_point(shot.global_position) and shot.has_method("clear"):
			shot.clear()
			last_bomb_projectiles_cleared += 1

# White full-screen flash (under the HUD), faded by _update_bomb_flash()
func _start_bomb_flash() -> void:
	if _bomb_flash == null:
		_bomb_flash = ColorRect.new()
		_bomb_flash.name = "BombFlash"
		_bomb_flash.color = Color(1, 1, 1, 1)
		_bomb_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bomb_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		$UI.add_child(_bomb_flash)
		$UI.move_child(_bomb_flash, 0)
	_bomb_flash_left = BOMB_FLASH_TIME
	_bomb_flash.modulate.a = BOMB_FLASH_ALPHA
	_bomb_flash.visible = true

# Accumulator (runs in _process, so it freezes while paused)
func _update_bomb_flash(delta: float) -> void:
	if _bomb_flash_left <= 0.0:
		return
	_bomb_flash_left -= delta
	if _bomb_flash_left <= 0.0:
		_bomb_flash_left = 0.0
		_bomb_flash.visible = false
		return
	_bomb_flash.modulate.a = BOMB_FLASH_ALPHA * (_bomb_flash_left / BOMB_FLASH_TIME)

func is_bomb_flash_visible() -> bool:
	return _bomb_flash != null and _bomb_flash.visible

func _on_object_hit(object: Node2D) -> void:
	# No damage once the run has ended (e.g. stray boss shots after victory)
	if current_state != GameState.PLAYING:
		return
	if not (object is Obstacle) or player.is_dead:
		return
	# Shield bubble: an offensive window (even during the hit blink)
	if player.is_shielded():
		_on_shielded_contact(object)
		return
	if not player.is_blinking:
		update_health(-object.damage)
		player.start_blink()  # Start the blink effect

# Contact with an obstacle while shielded: no health loss, the ring pops.
#  - rammed ordinary obstacle (obstacle.gd handle_player_collision() destroys
#    it after this returns): its kill points go through award_kill_points(),
#    so the combo applies (and the `destroyed` hook skips it)
#  - boss / blimp contact (they survive rams): they take
#    GameConfig.shield_ram_damage per contact hit (their contact rate limit)
#  - mine blast (the mine detonated itself): absorbed, nothing else
func _on_shielded_contact(object: Obstacle) -> void:
	_absorb_shield_hit()
	if object.is_being_collected:
		shield_ram_kills += 1
		award_kill_points(absi(object.points), object)
	elif not ("detonation_count" in object) and object.is_active:
		object.take_damage(config.shield_ram_damage)

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
	_reset_combo()

	# Create player explosion before hiding the player
	create_player_explosion()

	# Call the player's die function (also ends a shield)
	player.die()
	game_hud.update_shield(0.0)

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
	# Spawn the zone's weapon upgrade (once per zone per run) if it asks for one
	if current_zone_def and current_zone_def.spawns_weapon_upgrade \
			and not weapon_upgrades_spawned.has(current_zone):
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

	# Threat indicator only where waves play (the boss zone has the boss bar)
	game_hud.set_threat_visible(not zone.waves.is_empty())
	_last_threat_level = -1

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
	if boss.has_signal("phase_changed"):
		boss.connect("phase_changed", _on_boss_phase_changed)

# Phases 2+ (phase 1 is the fight start): big shake and a health cell drop
func _on_boss_phase_changed(phase: int) -> void:
	if phase >= 2 and current_state == GameState.PLAYING:
		shake(SHAKE_LARGE, SHAKE_LARGE_TIME)
		_drop_boss_health_cell()

# One health cell below the boss (deferred: phase changes come from shot
# hits inside physics callbacks)
func _drop_boss_health_cell() -> void:
	if not is_instance_valid(boss):
		return
	var scene: PackedScene = spawn_manager.get_pickup_scene(&"health")
	if scene == null:
		return
	boss_health_drops += 1
	# Boss is a child of the SpawnManager: its position is in the manager's space
	spawn_manager.spawn_collectible_at.call_deferred(boss.position + BOSS_DROP_OFFSET, scene)

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
	# Health hit zero this frame but process_game() hasn't noticed yet: the
	# player died first, so it's a normal game over (no station)
	if current_health <= 0.0:
		game_over()
		return
	current_state = GameState.VICTORY
	_reset_combo()
	player.end_shield()
	game_hud.update_shield(0.0)
	game_hud.set_pause_button_visible(false)

	# Stop the run; the ship stays on screen (no explosion)
	spawn_manager.stop_spawning()
	cloud_manager.stop_spawning()
	player.disable_movement()
	player.reset_input_state()

	game_hud.hide_boss_bar()
	show_message("ORBIT REACHED!")

	# Docking sequence: the station waits for the boss death sequence,
	# descends, the ship flies into the port, clamps close, DOCKED; then
	# _on_docking_finished awards the bonus and shows the results. All of it
	# runs on node-bound tweens, so nothing resumes if the level is freed.
	_start_docking()

func _start_docking() -> void:
	docking_station = DOCKING_STATION_SCENE.instantiate()
	docking_station.position = Vector2(get_viewport_rect().size.x / 2.0, docking_station.start_y)
	add_child(docking_station)
	docking_station.ready_for_ship.connect(_on_station_ready_for_ship)
	docking_station.clamps_closed.connect(_on_station_clamps_closed)
	docking_station.docking_finished.connect(_on_docking_finished, CONNECT_ONE_SHOT)
	docking_station.play_docking(player)

func _on_station_ready_for_ship() -> void:
	if current_state != GameState.VICTORY or not is_instance_valid(docking_station):
		return
	player.fly_to(docking_station.get_dock_position(), docking_station.ship_fly_time)

func _on_station_clamps_closed() -> void:
	shake(SHAKE_CLAMP, SHAKE_CLAMP_TIME)

func _on_docking_finished() -> void:
	if not is_inside_tree() or current_state != GameState.VICTORY:
		return
	victory_bonus = _health_percent() * VICTORY_BONUS_PER_HEALTH_PERCENT
	update_points(victory_bonus)
	_show_victory_screen()

# Health left as a whole percentage of the ship's max_health (0..100)
func _health_percent() -> int:
	if max_health <= 0.0:
		return 0
	return int(round(current_health / max_health * 100.0))

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

# Spawn the current zone's weapon upgrade pickup, unless the weapon is
# already maxed out (counting pickups still waiting to be collected); in that
# case it is retried while the zone lasts (e.g. after losing a tier).
func spawn_weapon_upgrade() -> void:
	if not weapon_upgrade_scene or weapon_upgrades_spawned.has(current_zone):
		return
	_live_weapon_upgrades = _live_weapon_upgrades.filter(
		func(pickup): return is_instance_valid(pickup) and not pickup.is_queued_for_deletion())
	if player.weapon_tier + _live_weapon_upgrades.size() >= player.max_weapon_tier:
		return

	weapon_upgrades_spawned[current_zone] = true

	# Create the upgrade collectible
	var upgrade = weapon_upgrade_scene.instantiate()
	# The zone it belongs to (its collection schedules that zone's mini-boss)
	upgrade.set_meta(&"zone_id", current_zone)
	add_child(upgrade)
	_live_weapon_upgrades.append(upgrade)

	# Calculate spawn position - centered horizontally and just above screen
	var viewport_rect = get_viewport_rect()
	var spawn_x = viewport_rect.size.x / 2
	var spawn_y = -100

	# Initialize the collectible
	upgrade.initialize(Vector2(spawn_x, spawn_y))

	# Not spawned by the spawn manager, so wire its signals here (awards its points)
	_on_object_spawned(upgrade)

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
