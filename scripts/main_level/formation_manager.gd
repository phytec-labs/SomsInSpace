# formation_manager.gd
# Spawns and flies wave formations (see docs/WAVE_DESIGN.md).
#
# create_path_formation() spawns a WaveGroup's members together at the start
# of its EntryPath and then moves the formation center along the path by
# distance (px/s); each member sits at center + its shape offset (SWARM adds a
# sway and a per-member jitter). After the curve ends the path's end_mode takes
# over (descend / hover then descend / exit along the last tangent).
# The formation also runs the group's fire pattern (VOLLEY / RIPPLE) for
# members that can shoot; INDIVIDUAL leaves members on their own shooting.
#
# create_single_group() spawns scene_override singles (blimp, UFO, ...), which
# fly on their own; they are tracked like a formation so the WaveManager can
# wait for them to clear.
#
# Members are pooled by the SpawnManager when they are destroyed or leave the
# screen; a formation is "cleared" once none of its members is still the live
# spawn it was (is_active and the same spawn_count).
#
# Pause-safe: everything runs from _process() delta.
class_name FormationManager
extends Node2D

const FormationSettingsScript := preload("res://scripts/data/formation_settings.gd")
const EntryPathScript := preload("res://scripts/data/entry_path.gd")

signal formation_created(formation_id: int, members: Array)

# Formation types (member offsets from the formation center)
enum FormationType {
	LINE,         # Simple horizontal line
	V_SHAPE,      # V formation
	SQUARE,       # Square/rectangle group
	DIAGONAL,     # Diagonal line
	WAVE,         # Wave/sine pattern
	CIRCLE,       # Circle/arc formation
	RANDOM,       # Fixed pseudo-random cluster
	SWARM,        # Loose cluster; sways, members jitter (FormationSettings "Swarm")
}

# How a formation's members shoot (WaveGroup.fire_mode)
enum FireMode {
	NONE,        # Never
	VOLLEY,      # Every fire_interval, every live member that can shoot fires
	RIPPLE,      # Every fire_interval, members fire in order RIPPLE_STEP apart
	INDIVIDUAL,  # Members keep their own random shooting (Obstacle default)
}

const PATH_DIR := "res://data/paths/"
const RIPPLE_STEP: float = 0.12
# Members that have been on screen are released once this far outside it
const CULL_MARGIN: float = 120.0
# Angular frequency (rad/s) of the HOLD_THEN_DESCEND sway
const HOLD_SWAY_FREQUENCY: float = 1.3

# Current zone's formation tuning (FormationSettings; see set_zone())
var settings: FormationSettingsScript
var current_formation_id: int = 0  # Used to generate unique IDs for formations
var active_formations: Dictionary = {}  # formation id -> formation state (Dictionary)
var rng = RandomNumberGenerator.new()

var _paths: Dictionary = {}         # path id -> EntryPath (null if missing)
var _pixel_curves: Dictionary = {}  # "id|mirrored|WxH" -> Curve2D in pixels

func _ready() -> void:
	rng.randomize()

# Sets the current zone (a ZoneDefinition) to adjust formation settings.
# Formations already flying keep going.
func set_zone(zone: Resource) -> void:
	if zone and zone.formation_settings:
		settings = zone.formation_settings
	else:
		push_warning("FormationManager: zone has no FormationSettings; keeping previous settings")

func _get_settings() -> FormationSettingsScript:
	if settings == null:
		settings = FormationSettingsScript.new()
	return settings

func _get_spawn_manager() -> Node:
	return get_parent()

# --- Paths ---

# EntryPath with the given id from res://data/paths/, or null
func get_path_resource(id: StringName) -> EntryPathScript:
	if _paths.has(id):
		return _paths[id]
	var file := PATH_DIR + String(id) + ".tres"
	var path: EntryPathScript = null
	if ResourceLoader.exists(file):
		path = load(file) as EntryPathScript
	if path == null:
		push_error("FormationManager: entry path '%s' not found (%s)" % [id, file])
	_paths[id] = path
	return path

func _get_pixel_curve(path: EntryPathScript, mirrored: bool) -> Curve2D:
	var size := _get_viewport_rect().size
	var key := "%s|%s|%dx%d" % [path.id, mirrored, int(size.x), int(size.y)]
	if not _pixel_curves.has(key):
		_pixel_curves[key] = path.build_pixel_curve(size, mirrored)
	return _pixel_curves[key]

# First point of the path in pixels (mirrored if asked)
func get_path_start(path_id: StringName, mirrored: bool) -> Vector2:
	var path := get_path_resource(path_id)
	if path == null:
		return Vector2(_get_viewport_rect().size.x / 2.0, -100.0)
	var curve := _get_pixel_curve(path, mirrored)
	if curve.point_count == 0:
		return Vector2(_get_viewport_rect().size.x / 2.0, -100.0)
	return curve.get_point_position(0)

# A point a little way along the path (for pointing the telegraph marker)
func get_path_point(path_id: StringName, mirrored: bool, distance: float) -> Vector2:
	var path := get_path_resource(path_id)
	if path == null:
		return get_path_start(path_id, mirrored)
	var curve := _get_pixel_curve(path, mirrored)
	return curve.sample_baked(minf(distance, curve.get_baked_length()))

# --- Spawning ---

# Spawn `group` (a WaveGroup) as a formation flying its EntryPath. mirrored
# flips the path and the member offsets about the screen center; speed_mult
# scales the path and descend speeds (difficulty ramp). Members spawn through
# SpawnManager.spawn_scene(), so the obstacle cap applies: a capped formation
# just has fewer members. Returns the formation id, or -1 if nothing spawned.
func create_path_formation(group: Resource, zone: Resource, mirrored: bool, speed_mult: float = 1.0) -> int:
	if zone and zone.formation_settings and settings == null:
		settings = zone.formation_settings
	var s := _get_settings()
	var path := get_path_resource(group.path)
	var spawn_manager = _get_spawn_manager()
	if path == null or group.enemy_scene == null or spawn_manager == null:
		return -1

	var curve := _get_pixel_curve(path, mirrored)
	var length := curve.get_baked_length()
	var start := curve.sample_baked(0.0) if curve.point_count > 0 else get_path_start(group.path, mirrored)

	var formation_type: FormationType = group.formation as FormationType
	var count: int = maxi(group.count, 1)
	var spread: float = group.spread
	if spread <= 0.0:
		spread = s.swarm_radius if formation_type == FormationType.SWARM else s.default_spread

	current_formation_id += 1
	var formation_id := current_formation_id
	var members: Array = []
	for i in range(count):
		var offset := get_formation_position(formation_type, i, count, spread)
		if mirrored:
			offset.x = -offset.x
		var node = spawn_manager.spawn_scene(group.enemy_scene, start + offset)
		if node == null:
			break  # Obstacle cap: the rest would be capped too
		var driven := false
		if node.has_method("set_formation_data"):
			node.set_formation_data(formation_id, offset)
			driven = node.get("formation_id") == formation_id
		if driven:
			if node.has_method("set_use_formation_movement"):
				node.set_use_formation_movement(true)
			if "fire_controlled" in node:
				node.fire_controlled = group.fire_mode != FireMode.INDIVIDUAL
		members.append(_make_member(node, offset, driven))

	if members.is_empty():
		return -1

	var speed: float = (group.path_speed if group.path_speed > 0.0 else path.default_speed) * speed_mult
	var formation := {
		"id": formation_id,
		"label": group.describe() if group.has_method("describe") else "",
		"members": members,
		"driven": true,
		"type": formation_type,
		"mirrored": mirrored,
		"curve": curve,
		"length": length,
		"distance": 0.0,
		"speed": maxf(speed, 1.0),
		"descend_speed": path.descend_speed * speed_mult,
		"end_mode": path.end_mode,
		"hold_seconds": (group.hold_seconds if group.hold_seconds > 0.0 else path.hold_seconds) / maxf(speed_mult, 0.01),
		"hold_elapsed": 0.0,
		"hold_x": 0.0,
		"sway_amplitude": path.hold_sway_amplitude,
		"exit_direction": _end_tangent(curve, length),
		"base": start,
		"time": 0.0,
		"fire_mode": group.fire_mode,
		"fire_interval": group.fire_interval,
		"first_fire_delay": group.first_fire_delay,
		"fire_armed": false,  # Set once a member is on screen
		"fire_timer": 0.0,
		"ripple_index": -1,
		"ripple_timer": 0.0,
	}

	if formation_type == FormationType.SWARM:
		# Per-member jitter: Vector2(phase, angular speed)
		var variation := s.swarm_jitter_speed_variation
		for m in members:
			m.jitter = Vector2(rng.randf() * TAU,
				s.swarm_jitter_speed * rng.randf_range(1.0 - variation, 1.0 + variation))
		formation.jitter_radius = s.swarm_jitter_radius
		formation.swarm_amplitude = s.swarm_sine_amplitude
		formation.swarm_frequency = s.swarm_sine_frequency

	active_formations[formation_id] = formation
	formation_created.emit(formation_id, members.map(func(m): return m.node))
	return formation_id

# scene_override groups: `count` single instances of the scene, spread
# horizontally around the path's start point (mirrored if asked). They fly on
# their own; the record only tracks them for clear checks. Returns the id or -1.
func create_single_group(group: Resource, mirrored: bool) -> int:
	var spawn_manager = _get_spawn_manager()
	if group.scene_override == null or spawn_manager == null:
		return -1
	var start := get_path_start(group.path, mirrored)
	var count: int = maxi(group.count, 1)
	var spread: float = group.spread if group.spread > 0.0 else _get_settings().default_spread * 2.0
	current_formation_id += 1
	var formation_id := current_formation_id
	var members: Array = []
	for i in range(count):
		var x := (float(i) - float(count - 1) / 2.0) * spread
		var node = spawn_manager.spawn_scene(group.scene_override, start + Vector2(x, 0.0))
		if node == null:
			break
		members.append(_make_member(node, Vector2(x, 0.0), false))
	if members.is_empty():
		return -1
	active_formations[formation_id] = {
		"id": formation_id,
		"label": group.describe() if group.has_method("describe") else "",
		"members": members,
		"driven": false,
		"fire_mode": FireMode.INDIVIDUAL,
		"time": 0.0,
	}
	formation_created.emit(formation_id, members.map(func(m): return m.node))
	return formation_id

func _make_member(node: Node, offset: Vector2, driven: bool) -> Dictionary:
	return {
		"node": node,
		"spawn": node.get("spawn_count"),
		"offset": offset,
		"driven": driven,
		"entered": false,
		"jitter": Vector2.ZERO,
	}

# --- Queries ---

# Formations (and scene_override groups) with at least one live member
func get_formations_on_screen() -> int:
	var n := 0
	for formation in active_formations.values():
		if _live_count(formation) > 0:
			n += 1
	return n

# True once every member of the formation is dead, pooled or gone
func is_formation_cleared(formation_id: int) -> bool:
	if not active_formations.has(formation_id):
		return true
	return _live_count(active_formations[formation_id]) == 0

func get_live_count(formation_id: int) -> int:
	if not active_formations.has(formation_id):
		return 0
	return _live_count(active_formations[formation_id])

func _is_member_alive(m: Dictionary) -> bool:
	var node = m.node
	return is_instance_valid(node) and node.is_active and node.get("spawn_count") == m.spawn

func _live_count(formation: Dictionary) -> int:
	var n := 0
	for m in formation.members:
		if _is_member_alive(m):
			n += 1
	return n

# --- Update ---

func _process(delta: float) -> void:
	for formation_id in active_formations.keys():
		var formation: Dictionary = active_formations[formation_id]
		if _live_count(formation) == 0:
			active_formations.erase(formation_id)
			continue
		formation.time += delta
		if formation.driven:
			_advance(formation, delta)
			_place_members(formation)
			_update_fire(formation, delta)
			_cull_members(formation)

# Move the formation center along its path, then apply the end mode
func _advance(f: Dictionary, delta: float) -> void:
	var curve: Curve2D = f.curve
	if f.distance < f.length:
		f.distance = minf(f.distance + f.speed * delta, f.length)
		f.base = curve.sample_baked(f.distance)
		f.hold_x = f.base.x
		return
	var end_mode: int = f.end_mode
	var base: Vector2 = f.base
	if end_mode == EntryPathScript.EndMode.HOLD_THEN_DESCEND and f.hold_elapsed < f.hold_seconds:
		f.hold_elapsed += delta
		base.x = f.hold_x + sin(f.hold_elapsed * HOLD_SWAY_FREQUENCY) * f.sway_amplitude
	elif end_mode == EntryPathScript.EndMode.EXIT:
		base += f.exit_direction * f.speed * delta
	else:
		base.y += f.descend_speed * delta
	f.base = base

func _end_tangent(curve: Curve2D, length: float) -> Vector2:
	if length <= 1.0:
		return Vector2.DOWN
	var a := curve.sample_baked(maxf(length - 12.0, 0.0))
	var b := curve.sample_baked(length)
	var dir := (b - a).normalized()
	return dir if dir != Vector2.ZERO else Vector2.DOWN

func _place_members(f: Dictionary) -> void:
	var sway := Vector2.ZERO
	if f.type == FormationType.SWARM:
		sway.x = sin(f.time * f.swarm_frequency) * f.swarm_amplitude
	for m in f.members:
		if not m.driven or not _is_member_alive(m):
			continue
		var pos: Vector2 = f.base + m.offset + sway
		if f.type == FormationType.SWARM:
			var j: Vector2 = m.jitter
			var a: float = f.time * j.y + j.x
			pos += Vector2(cos(a), sin(a * 1.3)) * f.jitter_radius
		m.node.global_position = pos

# Release members that were on screen and have now left it (paths can carry
# them off a side, e.g. EXIT paths); the bottom edge is handled by Obstacle
func _cull_members(f: Dictionary) -> void:
	var rect := _get_viewport_rect()
	var outer := rect.grow(CULL_MARGIN)
	for m in f.members:
		if not m.driven or not _is_member_alive(m):
			continue
		var pos: Vector2 = m.node.global_position
		if rect.has_point(pos):
			m.entered = true
		elif (m.entered or pos.y > rect.end.y) and not outer.has_point(pos):
			if m.node.has_method("force_screen_exit"):
				m.node.force_screen_exit()

func _update_fire(f: Dictionary, delta: float) -> void:
	var mode: int = f.fire_mode
	if (mode != FireMode.VOLLEY and mode != FireMode.RIPPLE) or f.fire_interval <= 0.0:
		return

	# A ripple in progress: next member every RIPPLE_STEP
	if f.ripple_index >= 0:
		f.ripple_timer += delta
		while f.ripple_index >= 0 and f.ripple_timer >= RIPPLE_STEP:
			f.ripple_timer -= RIPPLE_STEP
			# Skip members that can't fire so the rhythm stays even
			while f.ripple_index < f.members.size() and not _can_fire(f.members[f.ripple_index]):
				f.ripple_index += 1
			if f.ripple_index < f.members.size():
				f.members[f.ripple_index].node.shoot()
				f.ripple_index += 1
			if f.ripple_index >= f.members.size():
				f.ripple_index = -1

	# The fire clock starts when the first member comes on screen: the first
	# volley / ripple first_fire_delay later, then every fire_interval
	if not f.fire_armed:
		if not _any_member_on_screen(f):
			return
		f.fire_armed = true
		f.fire_timer = f.fire_interval - maxf(f.first_fire_delay, 0.0)
		return

	f.fire_timer += delta
	if f.fire_timer < f.fire_interval:
		return
	f.fire_timer = 0.0
	if mode == FireMode.VOLLEY:
		for m in f.members:
			if _can_fire(m):
				m.node.shoot()
	else:
		f.ripple_index = 0
		f.ripple_timer = RIPPLE_STEP  # First member fires on the next update

func _any_member_on_screen(f: Dictionary) -> bool:
	for m in f.members:
		if m.driven and _is_member_alive(m) and _is_on_screen(m.node.global_position):
			return true
	return false

func _is_on_screen(pos: Vector2) -> bool:
	var size := _get_viewport_rect().size
	return pos.y > 0.0 and pos.y < size.y and pos.x > 0.0 and pos.x < size.x

# Live, able to shoot, and on screen
func _can_fire(m: Dictionary) -> bool:
	if not m.driven or not _is_member_alive(m):
		return false
	var node = m.node
	if not node.get("can_shoot") or not node.has_method("shoot"):
		return false
	return _is_on_screen(node.global_position)

# --- Shapes ---

# Offset of member `index` of `count` from the formation center
func get_formation_position(formation_type: FormationType, index: int, count: int, spread: float) -> Vector2:
	match formation_type:
		FormationType.LINE:
			var x_pos = (index - (count - 1) / 2.0) * spread
			return Vector2(x_pos, 0)

		FormationType.V_SHAPE:
			var progress = index / float(count - 1) if count > 1 else 0.5
			var x_pos = (progress * 2 - 1) * spread
			var y_pos = abs(x_pos) * 0.5  # Creates a V shape
			return Vector2(x_pos, y_pos)

		FormationType.SQUARE:
			var side_length = int(ceil(sqrt(count)))
			var x_index = index % side_length
			var y_index = int(index / side_length)
			var x_pos = (x_index - (side_length - 1) / 2.0) * spread
			var y_pos = (y_index - (side_length - 1) / 2.0) * spread
			return Vector2(x_pos, y_pos)

		FormationType.DIAGONAL:
			var progress = index / float(count - 1) if count > 1 else 0.5
			var x_pos = (progress * 2 - 1) * spread
			var y_pos = x_pos
			return Vector2(x_pos, y_pos)

		FormationType.WAVE:
			var progress = index / float(count - 1) if count > 1 else 0.5
			var x_pos = (progress * 2 - 1) * spread * 1.5
			var y_pos = sin(progress * PI * 2) * spread * 0.3
			return Vector2(x_pos, y_pos)

		FormationType.CIRCLE:
			var angle = (index / float(count)) * PI * 2
			var x_pos = cos(angle) * spread
			var y_pos = sin(angle) * spread
			return Vector2(x_pos, y_pos)

		FormationType.SWARM:
			# Golden-angle scatter within `spread` (the swarm radius):
			# deterministic, evenly filled, no overlap checks needed
			var angle = index * 2.39996
			var radius = spread * sqrt((index + 0.5) / float(count))
			return Vector2(cos(angle) * radius, sin(angle) * radius * 0.7)

		FormationType.RANDOM:
			var temp_rng = RandomNumberGenerator.new()
			temp_rng.seed = index * 1000  # Deterministic randomness
			var x_pos = (temp_rng.randf() * 2 - 1) * spread
			var y_pos = (temp_rng.randf() * 2 - 1) * spread * 0.5
			return Vector2(x_pos, y_pos)

		_:
			var x_pos = (index - (count - 1) / 2.0) * spread
			return Vector2(x_pos, 0)

func _get_viewport_rect() -> Rect2:
	var viewport = get_viewport()
	if viewport:
		return viewport.get_visible_rect()
	# Fallback with default size if viewport isn't available
	return Rect2(0, 0, 720, 1280)
