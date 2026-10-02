# ufo_obstacle.gd
# Saucer with a tractor beam. Flies in to hover_y, then patrols slowly from
# side to side with its beam on: while the player is inside the beam it is
# pulled up toward the saucer (player.add_external_velocity) and drained
# (level.apply_drain, beam_damage_per_second: no weapon tier loss, no blink,
# and the blink doesn't protect from it; the beam is escaped by moving).
# After hover_duration it switches the beam off and leaves downward, so it
# never camps forever. Spawned only by scene_override wave groups (see
# data/zones/upper_atmosphere.tres and space.tres), not the random lists.
#
# Moves on its own (base_speed 0): it declines formations and ignores the
# spawn manager's movement pattern. While entering or hovering it is never
# culled as off-screen. If max_hovering UFOs are already hovering, a new one
# just flies through without stopping (no beam). Screen-clear bomb:
# bomb_resistant (set in the scene), so a bomb only deals
# GameConfig.bomb_boss_damage (150); its state, ring and bolt carry on.
#
# Pause-safe: _process/_physics_process only, no timers or tweens.
#
# Art: sprites/ufo_1.png (1024x512) on a level Sprite2D at 0.2079 (~210x80 px
# on screen); the hull is a horizontal CapsuleShape2D (200 x 52). The beam
# starts at the glowing emitter under the saucer (y 30, drawn behind the
# hull) and reaches 500 px down.
#
# Beam look: `Beam/Field`, a 200x520 ColorRect (mouse ignored) at (-100, 30)
# drawn only by shaders/ufo_beam.gdshader (procedural, no texture): UV
# (0.5, 0) is the emitter, the cone is 80 px wide there and ~160 px at the
# end of `Beam/BeamArea`'s polygon (y 530), then fades out by y 550. Keep
# the BeamArea polygon matching the cone (top_half_width / bottom_half_width
# are fractions of the 200 px quad width). Code drives two things:
# - Beam.modulate.a = fade (0 -> 1 over beam_fade_time when hovering starts,
#   back to 0 when leaving; the beam node hides at 0) * a gentle pulse
#   between beam_alpha_min and beam_alpha_max.
# - the shader's `capture` uniform: moves toward 1 while the player is in
#   the beam and back toward 0 otherwise, at 1 / capture_time per second.
# - the shader's `charge` (0..1, the bolt charge below) and `bolt` (1 -> 0
#   over bolt_flash_time when the bolt fires) uniforms.
#
# Weapons (group "UFO Weapons"), only while HOVERING and while the run is on:
# - Pulse ring: every ring_interval (the first ring_first_delay after the
#   hover starts) the saucer's lights flash for ring_telegraph seconds (a
#   self_modulate pulse on the sprite, so the hit flash still goes white on
#   top), then ring_bullets enemy shots (ring_scene at ring_speed px/s, set per
#   spawn; enemy_projectile.gd restores the authored speed when pooled) leave
#   the rim of the hull, evenly spaced. Every other ring is rotated by half a
#   spacing, so the gaps move.
# - Charged bolt: while the player stays inside the beam, a charge builds
#   over charge_time; outside the beam it drains in charge_decay_time. At full
#   charge the beam fires: bolt_damage to the player (through
#   level.update_health(), so the shield absorbs it with a ripple, the hit
#   blink protects, the combo resets and the tier-loss option applies; the
#   player then blinks like after a shot) and a bolt_flash_time white flash
#   down the beam; then bolt_cooldown before charging can start again. The
#   pull and the drain are unchanged.
# Gameplay timing for the bolt runs in _physics_process (with the pull); the
# ring and the visuals in _process. No timers or tweens: freezes while paused.
extends Obstacle
class_name UfoObstacle

enum State { ENTERING, HOVERING, LEAVING }

@export_group("UFO Movement")
## Height (px from the top) the saucer hovers at
@export var hover_y: float = 180.0
@export var enter_speed: float = 140.0
@export var leave_speed: float = 150.0
## Horizontal patrol speed (px/s) while hovering, bouncing between margins
@export var patrol_speed: float = 60.0
@export var side_margin: float = 90.0
## Seconds of hovering before it leaves downward
@export var hover_duration: float = 12.0
## Max UFOs hovering at once; extra ones fly through without stopping
@export var max_hovering: int = 2

@export_group("Tractor Beam")
## Upward velocity (px/s) added to the player each physics frame in the beam
@export var beam_pull_speed: float = 220.0
@export var beam_damage_per_second: float = 4.0
## Beam modulate alpha pulses between these values (the shader's own
## beam_alpha sets the base opacity)
@export_range(0.0, 1.0) var beam_alpha_min: float = 0.8
@export_range(0.0, 1.0) var beam_alpha_max: float = 1.0
@export var beam_pulse_speed: float = 6.0
## Seconds for the beam to fade in when hovering starts / out when leaving
@export var beam_fade_time: float = 0.3
## Seconds for the shader's `capture` to go 0 -> 1 (player caught) or back
@export var capture_time: float = 0.2

@export_group("UFO Weapons")
## Pulse ring: enemy shot scene, shots per ring, speed (px/s, set per spawn)
## and lifetime (s, set per spawn)
@export var ring_scene: PackedScene = preload("res://scenes/effects/enemy_projectile_3.tscn")
@export var ring_bullets: int = 12
@export var ring_speed: float = 150.0
@export var ring_lifetime: float = 9.0
## Seconds between rings, and from the start of the hover to the first ring
@export var ring_interval: float = 3.0
@export var ring_first_delay: float = 1.5
## Seconds the lights flash before each ring (the tell)
@export var ring_telegraph: float = 0.4
## Sprite self_modulate at the peak of the tell (two pulses)
@export var ring_telegraph_color: Color = Color(1.9, 1.6, 2.2, 1.0)
## Ring shots start on this ellipse around the hull center (rim of the saucer)
@export var ring_rim_radius: Vector2 = Vector2(96.0, 34.0)
## Bolt: seconds in the beam to fully charge; seconds for a full charge to
## drain once the player is out
@export var charge_time: float = 1.5
@export var charge_decay_time: float = 0.3
@export var bolt_damage: float = 25.0
## Seconds after a bolt before charging can start again
@export var bolt_cooldown: float = 2.0
## Seconds the white bolt flash takes to fade down the beam
@export var bolt_flash_time: float = 0.15

const HOVER_GROUP := &"ufo_hovering"

@onready var beam: Node2D = $Beam
@onready var beam_area: Area2D = $Beam/BeamArea
@onready var beam_field: CanvasItem = $Beam/Field

var state: State = State.ENTERING
var hover_time: float = 0.0
var _patrol_direction: float = 1.0
var _beam_time: float = 0.0
var _beam_on: bool = false
# Visual only: beam fade (0..1) and the shader's capture value (0..1)
var _beam_fade: float = 0.0
var _capture: float = 0.0
# Set each physics frame the beam pulls the player
var _player_in_beam: bool = false
var _beam_material: ShaderMaterial = null
# Observability for tests / debugging: player frames spent in the beam
var beam_contact_frames: int = 0
# Weapons: ring clock (s of hovering counted for the ring), time of the next
# ring on that clock, rings fired this spawn (also picks the half-spacing
# offset), tell running
var _ring_clock: float = 0.0
var _next_ring_at: float = 0.0
var _ring_telegraph_on: bool = false
# Bolt charge (0..1), cooldown left (s), flash left (s)
var _charge: float = 0.0
var _bolt_cooldown_left: float = 0.0
var _bolt_flash_left: float = 0.0
# Observability (tests / tuning), per spawn: rings fired, bolts fired, bolts
# that reached the player (absorbed by the shield included; not while
# blinking), times the player left the beam with charge built up (> 0.1)
# before a bolt
var rings_fired: int = 0
var bolts_fired: int = 0
var bolts_hit: int = 0
var beam_escapes: int = 0
var _was_charging: bool = false

func _ready() -> void:
	super._ready()
	# Run before the player's physics step so the pull applies this frame
	process_physics_priority = -1
	# The beam only detects the player; nothing detects (or shoots) the beam
	beam_area.collision_layer = 0
	beam_area.collision_mask = 1
	if beam_field:
		_beam_material = beam_field.material as ShaderMaterial
	_set_beam(false)
	_reset_beam_visual()

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	state = State.ENTERING
	hover_time = 0.0
	_beam_time = 0.0
	beam_contact_frames = 0
	_patrol_direction = 1.0 if randf() < 0.5 else -1.0
	move_toward_center = false
	_reset_weapons()
	rings_fired = 0
	bolts_fired = 0
	bolts_hit = 0
	beam_escapes = 0
	_set_beam(false)
	_reset_beam_visual()

func deactivate() -> void:
	_reset_weapons()
	_set_beam(false)
	_reset_beam_visual()
	_leave_hover_group()
	super.deactivate()

# Flies on its own, never as part of a formation
func set_formation_data(_form_id: int, _form_offset: Vector2) -> void:
	pass

func set_use_formation_movement(_value: bool) -> void:
	use_formation_movement = false

func set_movement_pattern(_pattern: String) -> void:
	movement_pattern = "linear"

func is_hovering() -> bool:
	return is_active and state == State.HOVERING

func is_beam_on() -> bool:
	return _beam_on

func _process(delta: float) -> void:
	if not is_active:
		return

	# (replaces Obstacle._process(), so run the hit flash / punch here)
	_update_hit_feedback(delta)

	match state:
		State.ENTERING:
			_process_entering(delta)
		State.HOVERING:
			_process_hovering(delta)
		State.LEAVING:
			position.y += leave_speed * delta
			check_if_offscreen()

	if is_active:
		_update_beam_visual(delta)

func _process_entering(delta: float) -> void:
	var width = get_viewport_rect().size.x
	var target_x = clampf(position.x, side_margin, width - side_margin)
	position.x = move_toward(position.x, target_x, enter_speed * delta)
	position.y = move_toward(position.y, hover_y, enter_speed * delta)
	if is_equal_approx(position.y, hover_y) and is_equal_approx(position.x, target_x):
		if get_tree().get_nodes_in_group(HOVER_GROUP).size() >= max_hovering:
			state = State.LEAVING  # Crowded: fly through
		else:
			state = State.HOVERING
			hover_time = 0.0
			add_to_group(HOVER_GROUP)
			_set_beam(true)
			_ring_clock = 0.0
			_next_ring_at = ring_first_delay

func _process_hovering(delta: float) -> void:
	hover_time += delta
	var width = get_viewport_rect().size.x
	position.x += _patrol_direction * patrol_speed * delta
	if position.x >= width - side_margin:
		position.x = width - side_margin
		_patrol_direction = -1.0
	elif position.x <= side_margin:
		position.x = side_margin
		_patrol_direction = 1.0

	if hover_time >= hover_duration:
		state = State.LEAVING
		_reset_weapons()
		_set_beam(false)
		_leave_hover_group()
		return
	_update_ring(delta)

# --- Pulse ring ---

# Ring clock: tell during the last ring_telegraph seconds before each ring,
# then the ring. Stops (tell off) once the run is over.
func _update_ring(delta: float) -> void:
	if _is_run_over():
		_set_ring_telegraph(false, 0.0)
		return
	_ring_clock += delta
	# No tell for a ring the hover ends before
	if _next_ring_at >= hover_duration:
		return
	var tell_start := _next_ring_at - ring_telegraph
	if _ring_clock >= _next_ring_at:
		_set_ring_telegraph(false, 0.0)
		_fire_ring()
		_next_ring_at += maxf(ring_interval, 0.1)
	elif _ring_clock >= tell_start and ring_telegraph > 0.0:
		# Two quick pulses over the tell
		var phase := (_ring_clock - tell_start) / ring_telegraph
		_set_ring_telegraph(true, absf(sin(phase * TAU)))

# Lights flash for the tell: sprite self_modulate (the hit flash mixes to
# white after it in the shader, so the two never fight)
func _set_ring_telegraph(on: bool, amount: float) -> void:
	if not on and not _ring_telegraph_on:
		return
	_ring_telegraph_on = on
	if sprite:
		sprite.self_modulate = Color.WHITE.lerp(ring_telegraph_color, amount) if on else Color.WHITE

func is_ring_telegraphing() -> bool:
	return _ring_telegraph_on

func _fire_ring() -> void:
	var count := maxi(ring_bullets, 0)
	if ring_scene == null or count == 0:
		return
	var spacing := TAU / float(count)
	# Alternate rings are rotated by half a spacing (gaps move)
	var offset := spacing * 0.5 * float(rings_fired % 2)
	rings_fired += 1
	var center := global_position + Vector2(0.0, 6.0)
	var parent := _get_effects_parent()
	for i in range(count):
		var dir := Vector2.RIGHT.rotated(offset + spacing * float(i))
		var shot = ObjectPool.acquire(ring_scene, parent)
		if shot == null:
			continue
		shot.speed = ring_speed
		shot.lifetime = ring_lifetime
		shot.initialize(center + dir * ring_rim_radius, dir)
	if shoot_audio_player and shoot_audio_player.stream:
		shoot_audio_player.pitch_scale = 0.7
		shoot_audio_player.play()

# Angle (rad) of the first shot of ring number `index` (0-based; tests)
func get_ring_offset(index: int) -> float:
	var count := maxi(ring_bullets, 1)
	return TAU / float(count) * 0.5 * float(index % 2)

func _is_run_over() -> bool:
	var level = get_tree().get_first_node_in_group("level")
	return level != null and level.has_method("_is_run_over") and level._is_run_over()

# Charge, cooldown, tell and flash back to rest (spawn, leaving, deactivate)
func _reset_weapons() -> void:
	_ring_clock = 0.0
	_next_ring_at = ring_first_delay
	_set_ring_telegraph(false, 0.0)
	_charge = 0.0
	_bolt_cooldown_left = 0.0
	_bolt_flash_left = 0.0
	_was_charging = false

func _physics_process(delta: float) -> void:
	_player_in_beam = false
	if not is_active or not _beam_on:
		return
	var caught: Node = null
	for area in beam_area.get_overlapping_areas():
		var player = area.get_parent()
		if player and player.is_in_group("player"):
			_apply_beam(player, delta)
			if _player_in_beam:
				caught = player
			break
	_update_charge(caught, delta)

# --- Charged bolt ---

# Charge builds while the player is in the beam (after the cooldown), drains
# fast outside it; at full charge the bolt fires at the player still inside
func _update_charge(caught: Node, delta: float) -> void:
	if _bolt_cooldown_left > 0.0:
		_bolt_cooldown_left = maxf(_bolt_cooldown_left - delta, 0.0)
	var can_charge := caught != null and _bolt_cooldown_left <= 0.0 and not _is_run_over()
	if can_charge:
		_charge += delta / charge_time if charge_time > 0.0 else 1.0
		if _charge > 0.1:
			_was_charging = true
		if _charge >= 1.0:
			_fire_bolt(caught)
	else:
		if caught == null and _was_charging:
			beam_escapes += 1
		_was_charging = false
		_charge = maxf(_charge - (delta / charge_decay_time if charge_decay_time > 0.0 else 1.0), 0.0)

func _fire_bolt(player: Node) -> void:
	_charge = 0.0
	_was_charging = false
	_bolt_cooldown_left = bolt_cooldown
	_bolt_flash_left = bolt_flash_time
	bolts_fired += 1
	var level = get_tree().get_first_node_in_group("level")
	if level == null or not level.has_method("update_health"):
		return
	# Same rules as an enemy shot (enemy_projectile.gd): the shield absorbs it
	# (ripple from above the ship), the hit blink protects
	var shielded: bool = player.has_method("is_shielded") and player.is_shielded()
	var blinking: bool = "is_blinking" in player and player.is_blinking
	var at: Vector2 = player.global_position + Vector2(0.0, -60.0)
	if shielded:
		bolts_hit += 1
		level.update_health(-bolt_damage, at)
	elif not blinking:
		bolts_hit += 1
		level.update_health(-bolt_damage, at)
		if player.has_method("start_blink"):
			player.start_blink()

# Observability (tests): bolt charge 0..1, cooldown left, flash running
func get_charge() -> float:
	return _charge

func get_bolt_cooldown_left() -> float:
	return _bolt_cooldown_left

func is_charging() -> bool:
	return _player_in_beam and _charge > 0.0

func _apply_beam(player: Node, delta: float) -> void:
	var alive: bool
	if player.has_method("is_alive"):
		alive = player.is_alive()
	else:
		alive = not ("is_dead" in player and player.is_dead)
	if not alive:
		return
	beam_contact_frames += 1
	_player_in_beam = true
	# Pull toward the saucer (skipped until the player supports it)
	if player.has_method("add_external_velocity"):
		player.add_external_velocity(Vector2(0.0, -beam_pull_speed))
	# Continuous drain, not a hit (see main_level.gd apply_drain())
	var level = get_tree().get_first_node_in_group("level")
	if level and level.has_method("apply_drain"):
		level.apply_drain(beam_damage_per_second, delta)

# Gameplay switch (pull / drain detection); the look fades on its own in
# _update_beam_visual()
func _set_beam(on: bool) -> void:
	_beam_on = on
	if not on:
		_player_in_beam = false
	if beam_area:
		beam_area.set_deferred("monitoring", on)

# Fade the beam toward on/off, pulse it, and ease `capture` toward whether
# the player is caught
func _update_beam_visual(delta: float) -> void:
	if beam == null:
		return
	var fade_step = delta / beam_fade_time if beam_fade_time > 0.0 else 1.0
	_beam_fade = move_toward(_beam_fade, 1.0 if _beam_on else 0.0, fade_step)
	var capture_step = delta / capture_time if capture_time > 0.0 else 1.0
	var caught = _beam_on and _player_in_beam
	_capture = move_toward(_capture, 1.0 if caught else 0.0, capture_step)
	if _bolt_flash_left > 0.0:
		_bolt_flash_left = maxf(_bolt_flash_left - delta, 0.0)
	var bolt := _bolt_flash_left / bolt_flash_time if bolt_flash_time > 0.0 else 0.0
	if _beam_material:
		_beam_material.set_shader_parameter("capture", _capture)
		_beam_material.set_shader_parameter("charge", _charge if _beam_on else 0.0)
		_beam_material.set_shader_parameter("bolt", bolt)

	beam.visible = _beam_fade > 0.0
	if beam.visible:
		_beam_time += delta
		var pulse = 0.5 + 0.5 * sin(_beam_time * beam_pulse_speed)
		# The bolt flash shows at full opacity whatever the pulse
		beam.modulate.a = maxf(_beam_fade * lerpf(beam_alpha_min, beam_alpha_max, pulse), bolt)

func _reset_beam_visual() -> void:
	_beam_fade = 0.0
	_capture = 0.0
	_player_in_beam = false
	if _beam_material:
		_beam_material.set_shader_parameter("capture", 0.0)
		_beam_material.set_shader_parameter("charge", 0.0)
		_beam_material.set_shader_parameter("bolt", 0.0)
	if beam:
		beam.visible = false
		beam.modulate.a = 0.0

# Observability (tests): visual beam fade and the shader's capture value
func get_beam_fade() -> float:
	return _beam_fade

func get_beam_capture() -> float:
	return _capture

func _leave_hover_group() -> void:
	if is_in_group(HOVER_GROUP):
		remove_from_group(HOVER_GROUP)

# Only culled once it is leaving (the hover can sit near the top edge)
func check_if_offscreen() -> void:
	if state == State.LEAVING:
		super.check_if_offscreen()
