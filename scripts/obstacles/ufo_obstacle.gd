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
# just flies through without stopping (no beam).
#
# Pause-safe: _process/_physics_process only, no timers or tweens.
#
# Art: sprites/ufo_1.png (1024x512) on a level Sprite2D at 0.2079 (~210x80 px
# on screen); the hull is a horizontal CapsuleShape2D (200 x 52). The beam
# starts at the glowing emitter under the saucer (y 30, drawn behind the
# hull) and reaches 500 px down.
# PLACEHOLDER_ART: scenes/obstacles/ufo_obstacle.tscn `Beam/BeamPolygon` is a
# flat translucent cyan trapezoid (80 px wide at the saucer, 160 px at the
# bottom); swap it for a beam texture/shader and keep `Beam/BeamArea`'s
# polygon matching its shape.
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
## Beam alpha pulses between these values
@export_range(0.0, 1.0) var beam_alpha_min: float = 0.25
@export_range(0.0, 1.0) var beam_alpha_max: float = 0.6
@export var beam_pulse_speed: float = 6.0

const HOVER_GROUP := &"ufo_hovering"

@onready var beam: Node2D = $Beam
@onready var beam_area: Area2D = $Beam/BeamArea

var state: State = State.ENTERING
var hover_time: float = 0.0
var _patrol_direction: float = 1.0
var _beam_time: float = 0.0
var _beam_on: bool = false
# Observability for tests / debugging: player frames spent in the beam
var beam_contact_frames: int = 0

func _ready() -> void:
	super._ready()
	# Run before the player's physics step so the pull applies this frame
	process_physics_priority = -1
	# The beam only detects the player; nothing detects (or shoots) the beam
	beam_area.collision_layer = 0
	beam_area.collision_mask = 1
	_set_beam(false)

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	state = State.ENTERING
	hover_time = 0.0
	_beam_time = 0.0
	beam_contact_frames = 0
	_patrol_direction = 1.0 if randf() < 0.5 else -1.0
	move_toward_center = false
	_set_beam(false)

func deactivate() -> void:
	_set_beam(false)
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

	_beam_time += delta
	var pulse = 0.5 + 0.5 * sin(_beam_time * beam_pulse_speed)
	beam.modulate.a = lerpf(beam_alpha_min, beam_alpha_max, pulse)

	if hover_time >= hover_duration:
		state = State.LEAVING
		_set_beam(false)
		_leave_hover_group()

func _physics_process(delta: float) -> void:
	if not is_active or not _beam_on:
		return
	for area in beam_area.get_overlapping_areas():
		var player = area.get_parent()
		if player and player.is_in_group("player"):
			_apply_beam(player, delta)
			break

func _apply_beam(player: Node, delta: float) -> void:
	var alive: bool
	if player.has_method("is_alive"):
		alive = player.is_alive()
	else:
		alive = not ("is_dead" in player and player.is_dead)
	if not alive:
		return
	beam_contact_frames += 1
	# Pull toward the saucer (skipped until the player supports it)
	if player.has_method("add_external_velocity"):
		player.add_external_velocity(Vector2(0.0, -beam_pull_speed))
	# Continuous drain, not a hit (see main_level.gd apply_drain())
	var level = get_tree().get_first_node_in_group("level")
	if level and level.has_method("apply_drain"):
		level.apply_drain(beam_damage_per_second, delta)

func _set_beam(on: bool) -> void:
	_beam_on = on
	if beam:
		beam.visible = on
	if beam_area:
		beam_area.set_deferred("monitoring", on)

func _leave_hover_group() -> void:
	if is_in_group(HOVER_GROUP):
		remove_from_group(HOVER_GROUP)

# Only culled once it is leaving (the hover can sit near the top edge)
func check_if_offscreen() -> void:
	if state == State.LEAVING:
		super.check_if_offscreen()
