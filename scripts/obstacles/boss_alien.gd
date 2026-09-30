# boss_alien.gd
# Alien Mothership boss. Spawned by SpawnManager.spawn_boss(), which positions
# it above the screen and calls initialize(); the boss then flies in, fights in
# three phases (by health thirds) and plays a death sequence before emitting
# `destroyed` so the spawn manager can pool it.
#
# All timing uses _process() delta accumulators and node-bound tweens, so the
# fight freezes while the tree is paused.
extends Obstacle
class_name BossAlien

# Entrance finished; the boss can now be damaged
signal fight_started
signal health_changed(current: float, max: float)
# 1 at fight start, then 2 and 3 as health crosses the thirds
signal phase_changed(phase: int)
# Health reached zero (emitted once, before the death sequence)
signal defeated

@export var boss_name: String = "Alien Mothership"
@export var minion_scene: PackedScene = preload("res://scenes/obstacles/alien_obstacle_1.tscn")

@export_group("Boss Tuning")
@export var fight_y: float = 220.0            # Hover height once the fight starts
@export var entrance_time: float = 2.5        # Seconds to fly in from spawn
@export var max_minions: int = 4              # Live summoned minions allowed
@export var volley_spread_degrees: float = 35.0 # Fan half-angle
@export var volley_projectiles: int = 3       # Per gun point
## From this phase on each volley fires from ONE gun point, cycling
## left -> center -> right -> center; earlier phases fire every gun point
## at once (0 = always all gun points)
@export var alternate_volley_from_phase: int = 3
@export var contact_hit_interval: float = 0.5 # Re-hit while the player overlaps
@export var death_duration: float = 1.5
@export var death_explosions: int = 6

# Per-phase behaviour: drift angular speed (rad/s) and amplitude (px), and
# attack intervals in seconds (0 = attack not used in that phase)
const PHASES := {
	1: {"drift_speed": 0.6, "drift_amplitude": 200.0, "aimed": 1.2, "volley": 0.0, "summon": 0.0},
	2: {"drift_speed": 1.0, "drift_amplitude": 220.0, "aimed": 1.5, "volley": 2.0, "summon": 0.0},
	3: {"drift_speed": 1.5, "drift_amplitude": 230.0, "aimed": 1.2, "volley": 1.0, "summon": 6.0},
}
const ATTACK_ANIM_TIME: float = 0.5
const FLASH_TIME: float = 0.08
const BOB_AMPLITUDE: float = 12.0

var phase: int = 0
var _fight_started: bool = false
var _dying: bool = false
# Set by stand_down() (the run ended without a kill): hover, never attack
var _standing_down: bool = false
var _drift_time: float = 0.0
var _aimed_timer: float = 0.0
var _volley_timer: float = 0.0
var _summon_timer: float = 0.0
var _contact_timer: float = 0.0
var _attack_anim_timer: float = 0.0
var _volley_step: int = 0  # Position in the alternating gun point cycle
# Summoned minions: [node, its spawn_count at summon time]. A changed
# spawn_count means it was returned to the pool and reused for another spawn.
var _minions: Array = []

var _entrance_tween: Tween
var _flash_tween: Tween
var _death_tween: Tween

func _ready() -> void:
	# The boss flashes itself (_flash(), its hue-shift shader's `flash`
	# uniform) and has its own HUD health bar: no base hit flash / punch /
	# mini health bar
	_handles_own_flash = true
	show_health_bar = false
	super._ready()
	# The scene's shader material must not be shared between instances
	if animated_sprite and animated_sprite.material:
		animated_sprite.material = animated_sprite.material.duplicate()

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	_kill_tweens()

	phase = 0
	_fight_started = false
	_dying = false
	_standing_down = false
	_drift_time = 0.0
	_aimed_timer = 0.0
	_volley_timer = 0.0
	_summon_timer = 0.0
	_contact_timer = 0.0
	_attack_anim_timer = 0.0
	_volley_step = 0
	_minions.clear()
	_set_flash(0.0)

	# Bosses never join formations or drift with the base movement code
	movement_pattern = "linear"
	speed_multiplier = 1.0

	_entrance_tween = create_tween()
	_entrance_tween.tween_property(self, "position:y", fight_y, entrance_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_entrance_tween.tween_callback(_start_fight)

func deactivate() -> void:
	_kill_tweens()
	_set_flash(0.0)
	super.deactivate()

func _start_fight() -> void:
	if not is_active or _dying or _standing_down:
		return
	_fight_started = true
	fight_started.emit()
	health_changed.emit(health, max_health)
	_enter_phase(1)

# The boss never leaves the screen and ignores formation/base movement
func check_if_offscreen() -> void:
	pass

func set_use_formation_movement(_value: bool) -> void:
	use_formation_movement = false

func _process(delta: float) -> void:
	if not is_active or _dying or not _fight_started:
		return

	_update_movement(delta)
	if _standing_down:
		return
	_update_attacks(delta)
	_update_contact(delta)

# Called by the level when the run ends while the boss is alive (player
# died): keep hovering but stop shooting, summoning and contact damage
func stand_down() -> void:
	_standing_down = true
	_attack_anim_timer = 0.0
	if is_active and not _dying:
		play_animation("idle")

func _update_movement(delta: float) -> void:
	var settings: Dictionary = PHASES[phase]
	_drift_time += delta * settings.drift_speed
	var center_x = get_viewport_rect().size.x / 2.0
	position.x = center_x + sin(_drift_time) * settings.drift_amplitude
	position.y = fight_y + sin(_drift_time * 2.0) * BOB_AMPLITUDE

func _update_attacks(delta: float) -> void:
	var settings: Dictionary = PHASES[phase]

	_aimed_timer += delta
	if _aimed_timer >= settings.aimed:
		_aimed_timer = 0.0
		_fire_aimed_shot()

	if settings.volley > 0.0:
		_volley_timer += delta
		if _volley_timer >= settings.volley:
			_volley_timer = 0.0
			_fire_volley()

	if settings.summon > 0.0:
		_summon_timer += delta
		if _summon_timer >= settings.summon:
			_summon_timer = 0.0
			_summon_minions()

	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta
		if _attack_anim_timer <= 0.0:
			play_animation("idle")

# Keep hurting the player while it stays inside the boss (area_entered only
# fires once); the level ignores hits while the player is blinking
func _update_contact(delta: float) -> void:
	_contact_timer = maxf(_contact_timer - delta, 0.0)
	if _contact_timer <= 0.0 and has_overlapping_areas():
		handle_player_collision()

func _enter_phase(new_phase: int) -> void:
	# Step through skipped phases so listeners see every transition
	while phase < new_phase:
		phase += 1
		_aimed_timer = 0.0
		_volley_timer = 0.0
		# Summon soon after entering the summoning phase
		_summon_timer = PHASES[phase].summon * 0.5
		phase_changed.emit(phase)

func _phase_for_health() -> int:
	if health > max_health * 2.0 / 3.0:
		return 1
	if health > max_health / 3.0:
		return 2
	return 3

# --- Attacks ---

func _fire_aimed_shot() -> void:
	if not projectile_scene or gun_points.is_empty():
		return
	_fire_from(gun_points[rng.randi() % gun_points.size()])

func _fire_volley() -> void:
	if not projectile_scene or gun_points.is_empty():
		return
	_play_attack_animation()
	var count = maxi(volley_projectiles, 1)
	for gun_point in _volley_gun_points():
		for i in range(count):
			var t = 0.5 if count == 1 else float(i) / float(count - 1)
			var angle = deg_to_rad(lerpf(-volley_spread_degrees, volley_spread_degrees, t))
			_fire_from_direction(gun_point, Vector2.DOWN.rotated(angle))

# Every gun point, or (from alternate_volley_from_phase on) a single one that
# ping-pongs across them (L, C, R, C, ... for three gun points)
func _volley_gun_points() -> Array:
	if alternate_volley_from_phase <= 0 or phase < alternate_volley_from_phase \
			or gun_points.size() <= 1:
		return gun_points
	var n = gun_points.size()
	var cycle = 2 * (n - 1)
	var step = _volley_step % cycle
	_volley_step += 1
	return [gun_points[step if step < n else cycle - step]]

# The base shoot() picks one random gun point with aiming; used by nothing in
# the boss loop but kept consistent in case something calls it
func shoot() -> void:
	if not is_active or _dying or _standing_down or not _fight_started:
		return
	_fire_aimed_shot()

func _play_attack_animation() -> void:
	play_animation("attack")
	_attack_anim_timer = ATTACK_ANIM_TIME

func _summon_minions() -> void:
	if not minion_scene:
		return
	var spawn_manager = get_tree().get_first_node_in_group("spawn_manager")
	if not spawn_manager or not spawn_manager.has_method("spawn_minion"):
		return

	var free_slots = max_minions - get_live_minion_count()
	var count = mini(rng.randi_range(2, 3), free_slots)
	if count <= 0:
		return

	_play_attack_animation()
	var width = get_viewport_rect().size.x
	for i in range(count):
		var offset_x = (float(i) - float(count - 1) / 2.0) * 90.0 + rng.randf_range(-15.0, 15.0)
		var pos = Vector2(clampf(global_position.x + offset_x, 60.0, width - 60.0),
			global_position.y + 110.0)
		var minion = spawn_manager.spawn_minion(minion_scene, pos)
		if minion:
			_minions.append([minion, minion.spawn_count])

# Summoned minions still alive (prunes dead / pooled ones)
func get_live_minion_count() -> int:
	for i in range(_minions.size() - 1, -1, -1):
		var minion = _minions[i][0]
		if not is_instance_valid(minion) or not minion.is_active \
				or minion.spawn_count != _minions[i][1]:
			_minions.remove_at(i)
	return _minions.size()

# --- Damage ---

func take_damage(amount: float) -> void:
	# Shots are absorbed during the entrance and the death sequence
	if not is_active or not _fight_started or _dying:
		return

	health = maxf(health - amount, 0.0)
	_flash()
	health_changed.emit(health, max_health)

	if health <= 0.0:
		_begin_death()
	else:
		_enter_phase(_phase_for_health())

# Touching the boss hurts the player, but the boss survives
func handle_player_collision() -> void:
	if not is_active or _dying or _standing_down:
		return
	_contact_timer = contact_hit_interval
	emit_signal("object_hit")

func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_set_flash(1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, 1.0, 0.0, FLASH_TIME)

# Whiteness of the sprite (shader uniform; falls back to an overbright modulate)
func _set_flash(amount: float) -> void:
	if not animated_sprite:
		return
	var mat = animated_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("flash", amount)
	else:
		animated_sprite.self_modulate = Color.WHITE.lerp(Color(3.0, 3.0, 3.0), amount)

# --- Death ---

func _begin_death() -> void:
	_dying = true
	defeated.emit()

	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if collision_polygon:
		collision_polygon.set_deferred("disabled", true)

	if _entrance_tween:
		_entrance_tween.kill()
	play_animation("attack")

	var count = maxi(death_explosions, 1)
	var interval = death_duration / float(count)
	_death_tween = create_tween()
	for i in range(count):
		_death_tween.tween_callback(_spawn_death_explosion.bind(false))
		_death_tween.tween_interval(interval)
	_death_tween.tween_callback(_finish_death)

func _spawn_death_explosion(large: bool) -> void:
	_flash()
	var offset = Vector2.ZERO if large else \
		Vector2(rng.randf_range(-80.0, 80.0), rng.randf_range(-60.0, 60.0))
	_play_explosion_sound()
	if not explosion_scene:
		return
	var explosion = ObjectPool.acquire(explosion_scene, _get_effects_parent())
	explosion.global_position = global_position + offset
	explosion.set_explosion_type(2 if large else 1)  # LARGE / MEDIUM
	explosion.start()

func _finish_death() -> void:
	_spawn_death_explosion(true)

	# Award points the same way the base obstacle does (through the level)
	_award_kill_points()

	deactivate()
	emit_signal("destroyed")

func _kill_tweens() -> void:
	for tween in [_entrance_tween, _flash_tween, _death_tween]:
		if tween:
			tween.kill()
	_entrance_tween = null
	_flash_tween = null
	_death_tween = null
