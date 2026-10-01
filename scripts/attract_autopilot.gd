# attract_autopilot.gd
# Flies the player during the attract-mode demo. Added by the AttractMode
# autoload as a child of the level; drives the player only through its public
# input state (is_touch_active / target_position / is_firing), exactly as a
# held finger would, so no gameplay code knows about the demo.
#
# Each frame (while the player can move): fire continuously and steer to a
# point in the bottom part of the screen whose x follows the nearest enemy
# (or wanted pickup) above the ship, blended with a slow sine sweep so the
# ship never sits still. Pickups are chased except the screen-clear bomb
# (IGNORED_PICKUPS): a bomb would empty the screen and the demo would look
# dead, so it is steered around like an enemy instead. Simple dodges shift the
# target sideways when an enemy shot is closing in or an enemy / bomb is about
# to reach the ship.
#
# Mini-boss focus: while a mini-boss (an obstacle whose `is_miniboss` property
# is true, read with get(): the blimp) is active and on screen, the x-tracking
# follows it instead of the nearest enemy, at MINIBOSS_TRACK_WEIGHT, so the
# demo shoots it down instead of letting it hold the waves. Dodges, pickup
# fetches (the weapon upgrade first) and bomb avoidance still override it.
#
# UFO beam: the cruise line sits below the tractor beam, but a fetch can climb
# into it. While a UFO's bolt is charging on the ship (`is_charging()`), the
# ship escapes sideways, BEAM_ESCAPE_X from the saucer's x (overrides any
# other dodge), well before the bolt fires.
#
# Fetch: a pickup worth climbing for pulls the target off the cruise line to
# the pickup itself (the ship flies there at its own speed; re-aimed every
# scan since the weapon upgrade sways), then the ship drops back to the
# cruise line once it is collected or gone:
#   - the weapon upgrade (hovering at ~40% of the screen, spawned directly
#     under the level) once it has settled, while the weapon is not maxed;
#     always preferred over other pickups
#   - other wanted pickups (health / shield / energy) above the cruise line
#     and within FETCH_RADIUS of the ship, nearest first (a pickup at the top
#     of the screen is not chased through a formation)
# Dodges still apply while fetching; a dodge pauses the climb (and the
# timeout) for its duration. A fetch is dropped while an obstacle is within
# FETCH_OBSTACLE_CLEARANCE of the pickup, and abandoned after FETCH_TIMEOUT s
# (that pickup is then left alone for FETCH_RETRY_DELAY s).
#
# Scene scans run every SCAN_INTERVAL frames and only read the spawn
# manager's children, the level's children and the `enemy_projectile` group.
extends Node

const ENEMY_PROJECTILE_GROUP := &"enemy_projectile"
const OBSTACLE_SCRIPT := preload("res://scripts/obstacles/obstacle.gd")
## Pickup types (get_pickup_type()) the demo never collects
const IGNORED_PICKUPS: Array[StringName] = [&"bomb"]
## Script-path fallback for pickups without get_pickup_type()
const IGNORED_PICKUP_SCRIPT_SUFFIXES: Array[String] = ["bomb_pickup.gd"]

## Frames between scene scans (target / threat updates)
const SCAN_INTERVAL := 3
## Ship cruise height as a fraction of the viewport height
const CRUISE_Y_FRACTION := 0.8
## Vertical bob of the cruise point (px) and its speed (rad/s)
const BOB_AMPLITUDE := 40.0
const BOB_SPEED := 0.9
## Sine sweep amplitude (fraction of the viewport width) and speed (rad/s)
const SWEEP_AMPLITUDE := 0.3
const SWEEP_SPEED := 0.55
## How strongly the target x follows the tracked enemy (vs. the sweep)
const TRACK_WEIGHT := 0.75
## Same for a tracked mini-boss (centered under it all tier-2 shots land)
const MINIBOSS_TRACK_WEIGHT := 1.0
## A mini-boss counts as on screen once its center is below this y (px above
## the top edge: the blimp's lower part is visible by then)
const MINIBOSS_VISIBLE_Y := -80.0
## Enemy shot dodge: horizontal trigger distance, look-ahead above the ship,
## sideways shift, and how long a dodge is held
const SHOT_DODGE_X := 90.0
const SHOT_LOOK_AHEAD := 220.0
const DODGE_SHIFT := 120.0
const DODGE_HOLD := 0.35
## Enemies closer than this (vertically) are dodged instead of tracked
const RAM_DISTANCE := 230.0
## Caught in a UFO beam with the bolt charging: target x this far from the
## saucer's x (the beam is at most ~80 px wide each side of it)
const BEAM_ESCAPE_X := 210.0
## Keep the target this far from the screen edges
const EDGE_MARGIN := 60.0
## Ignored pickups (bomb) are kept at least this far sideways from the ship
## target while they are between AVOID_ABOVE px above and AVOID_BELOW px below
## the ship
const AVOID_X := 130.0
const AVOID_ABOVE := 320.0
const AVOID_BELOW := 80.0
## Fetch: non-weapon pickups are climbed for only within this distance (px)
## of the ship
const FETCH_RADIUS := 350.0
## Fetch given up after this many seconds (dodge time not counted)
const FETCH_TIMEOUT := 4.0
## A given-up pickup is not fetched again for this long (s)
const FETCH_RETRY_DELAY := 3.0
## No fetch while an obstacle is this close (px) to the pickup
const FETCH_OBSTACLE_CLEARANCE := 90.0
## Pickup type of the weapon upgrade; script-path fallback
const WEAPON_PICKUP := &"weapon"
const WEAPON_PICKUP_SCRIPT_SUFFIX := "weapon_upgrade_collectible.gd"

var level: Node
var player: Node2D
var spawn_manager: Node

var _time: float = 0.0
var _frame: int = 0
var _track_x: float = NAN
var _track_is_miniboss: bool = false
var _dodge_x: float = 0.0
var _dodge_time_left: float = 0.0
# x of ignored pickups (bombs) near the ship's height, refreshed by _scan()
var _avoid_xs: Array[float] = []
# Script -> extends obstacle.gd (enemies are dodged when close; pickups aren't)
var _is_obstacle_script: Dictionary = {}
# Pickup being fetched (null: cruising), refreshed by _scan(); its position
# at the last scan; seconds spent on this fetch (excluding dodges)
var _fetch_node: Node2D = null
var _fetch_pos: Vector2 = Vector2.ZERO
var _fetch_time: float = 0.0
# Pickup instance id -> _time until which it is not fetched (timed out)
var _fetch_blocked: Dictionary = {}
# Observability (tests): scans that triggered a beam escape
var beam_escapes: int = 0


func setup(p_level: Node) -> void:
	level = p_level
	player = level.get("player") as Node2D
	spawn_manager = level.get("spawn_manager")
	if spawn_manager == null:
		spawn_manager = level.get_node_or_null("SpawnManager")


func _ready() -> void:
	name = "AttractAutopilot"
	if level == null:
		setup(get_parent())


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not player.get("can_move") or player.get("is_dead"):
		return
	_time += delta
	_dodge_time_left = maxf(0.0, _dodge_time_left - delta)

	_frame += 1
	if _frame % SCAN_INTERVAL == 0:
		_scan()

	var view := player.get_viewport_rect().size
	var center_x := view.x * 0.5
	var sweep_x := center_x + sin(_time * SWEEP_SPEED) * view.x * SWEEP_AMPLITUDE
	var x := sweep_x
	if not is_nan(_track_x):
		x = lerpf(sweep_x, _track_x, MINIBOSS_TRACK_WEIGHT if _track_is_miniboss else TRACK_WEIGHT)
	if _dodge_time_left > 0.0:
		x = _dodge_x
	# Set directly (not through update_target_position), so this is already
	# the final ship position: no touch_offset to subtract
	var y := view.y * CRUISE_Y_FRACTION + sin(_time * BOB_SPEED) * BOB_AMPLITUDE

	if is_fetching():
		if _dodge_time_left > 0.0:
			# Fetch paused: sidestep at the current height
			y = player.global_position.y
		else:
			_fetch_time += delta
			if _fetch_time > FETCH_TIMEOUT:
				_abandon_fetch()
			else:
				x = _fetch_pos.x
				y = _fetch_pos.y

	x = _avoid_ignored_pickups(x, player.global_position.x, view.x)
	x = clampf(x, EDGE_MARGIN, view.x - EDGE_MARGIN)

	player.set("target_position", Vector2(x, y))
	player.set("is_touch_active", true)
	player.set("is_firing", true)


func _scan() -> void:
	var ship: Vector2 = player.global_position
	_track_x = NAN
	_track_is_miniboss = false
	_avoid_xs.clear()
	var miniboss_x := NAN

	var view := player.get_viewport_rect().size
	# Fetch candidates (wanted pickups) and obstacle positions (fetch safety)
	var pickups: Array[Node2D] = []
	var obstacles: Array[Vector2] = []

	# Nearest active enemy (or wanted pickup) above the ship is tracked; an
	# enemy (or an ignored pickup) about to reach the ship is dodged
	var best_dist := INF
	if is_instance_valid(spawn_manager):
		for child in spawn_manager.get_children():
			if not (child is Node2D) or not child.visible or not child.get("is_active"):
				continue
			var pos: Vector2 = child.global_position
			var above := ship.y - pos.y
			var is_obstacle := _is_obstacle(child)
			if is_obstacle:
				obstacles.append(pos)
			elif child.has_method("get_pickup_type") and not is_ignored_pickup(child):
				pickups.append(child)
			if is_ignored_pickup(child):
				# Never steer toward it; keep clear while it passes the ship
				if above > -AVOID_BELOW and above < AVOID_ABOVE:
					_avoid_xs.append(pos.x)
				continue
			if above < -40.0:
				continue  # Already below the ship
			if above < RAM_DISTANCE and absf(pos.x - ship.x) < DODGE_SHIFT and is_obstacle:
				_start_dodge(ship.x, pos.x)
				continue
			if is_obstacle and child.has_method("is_charging") and child.is_charging():
				_start_beam_escape(ship.x, pos.x, view.x)
			if is_obstacle and child.get("is_miniboss") == true and _is_miniboss_on_screen(pos, view):
				miniboss_x = pos.x
			var dist := ship.distance_squared_to(pos)
			if dist < best_dist:
				best_dist = dist
				_track_x = pos.x

	# A mini-boss on screen is preferred over the nearest enemy
	if not is_nan(miniboss_x):
		_track_x = miniboss_x
		_track_is_miniboss = true

	# Enemy shots (enemy_projectile.gd adds itself to the group; pooled idle
	# shots are out of the tree, so not listed)
	for child in get_tree().get_nodes_in_group(ENEMY_PROJECTILE_GROUP):
		if not (child is Node2D):
			continue
		if not child.get("is_active") or not child.visible:
			continue
		var pos: Vector2 = child.global_position
		var above := ship.y - pos.y
		if above > -20.0 and above < SHOT_LOOK_AHEAD and absf(pos.x - ship.x) < SHOT_DODGE_X:
			_start_dodge(ship.x, pos.x)
			break

	# The weapon upgrade lives directly under the level (not pooled)
	if is_instance_valid(level):
		for child in level.get_children():
			if child is Node2D and child.get("is_active") and is_weapon_pickup(child):
				pickups.append(child)

	_update_fetch(ship, view, pickups, obstacles)


# Choose the pickup to fetch (see the header): the weapon upgrade first, then
# the nearest other wanted pickup in range; none -> back to cruising
func _update_fetch(ship: Vector2, view: Vector2, pickups: Array[Node2D], obstacles: Array[Vector2]) -> void:
	var cruise_y := view.y * CRUISE_Y_FRACTION
	var tier = player.get("weapon_tier")
	var max_tier = player.get("max_weapon_tier")
	var weapon_wanted: bool = tier != null and max_tier != null and tier < max_tier

	var best: Node2D = null
	var best_is_weapon := false
	var best_dist := INF
	for pickup in pickups:
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion() \
				or not pickup.visible or pickup.get("is_being_collected"):
			continue
		if _fetch_blocked.get(pickup.get_instance_id(), -1.0) > _time:
			continue
		var pos: Vector2 = pickup.global_position
		if pos.y < 0.0 or pos.y > view.y or pos.x < 0.0 or pos.x > view.x:
			continue  # Off screen
		var is_weapon := is_weapon_pickup(pickup)
		if is_weapon:
			# Wait until it has settled at its hover point (null: no such state)
			if not weapon_wanted or pickup.get("reached_middle") == false:
				continue
		else:
			if pos.y >= cruise_y or ship.distance_to(pos) > FETCH_RADIUS:
				continue
		if best_is_weapon and not is_weapon:
			continue
		var blocked := false
		for obstacle_pos in obstacles:
			if obstacle_pos.distance_to(pos) < FETCH_OBSTACLE_CLEARANCE:
				blocked = true
				break
		if blocked:
			continue
		var dist := ship.distance_squared_to(pos)
		if (is_weapon and not best_is_weapon) or dist < best_dist:
			best = pickup
			best_is_weapon = is_weapon
			best_dist = dist

	if best != _fetch_node:
		_fetch_node = best
		_fetch_time = 0.0
	if best != null:
		_fetch_pos = best.global_position

	# Forget expired blocks
	for id in _fetch_blocked.keys():
		if _fetch_blocked[id] <= _time:
			_fetch_blocked.erase(id)


# Mini-boss center on screen (or just above it, see MINIBOSS_VISIBLE_Y)
func _is_miniboss_on_screen(pos: Vector2, view: Vector2) -> bool:
	return pos.y > MINIBOSS_VISIBLE_Y and pos.y < view.y and pos.x > 0.0 and pos.x < view.x


## True while the ship is climbing for a pickup.
func is_fetching() -> bool:
	return _fetch_node != null and is_instance_valid(_fetch_node)


func _abandon_fetch() -> void:
	if is_instance_valid(_fetch_node):
		_fetch_blocked[_fetch_node.get_instance_id()] = _time + FETCH_RETRY_DELAY
	_fetch_node = null
	_fetch_time = 0.0


# Push target x at least AVOID_X away from every ignored pickup near the
# ship (to the ship's side of it; the other side when that is off screen)
func _avoid_ignored_pickups(x: float, ship_x: float, view_w: float) -> float:
	for ax in _avoid_xs:
		if absf(x - ax) >= AVOID_X:
			continue
		var dir := signf(ship_x - ax)
		if dir == 0.0:
			dir = 1.0 if ax < view_w * 0.5 else -1.0
		var candidate := ax + dir * AVOID_X
		if candidate < EDGE_MARGIN or candidate > view_w - EDGE_MARGIN:
			candidate = ax - dir * AVOID_X
		x = candidate
	return x


# Shift the target sideways, away from the threat at threat_x (towards the
# middle when the ship is near an edge)
func _start_dodge(ship_x: float, threat_x: float) -> void:
	if _dodge_time_left > 0.0:
		return
	var dir := signf(ship_x - threat_x)
	if dir == 0.0:
		dir = 1.0 if randf() < 0.5 else -1.0
	var view_w := player.get_viewport_rect().size.x
	if ship_x + dir * DODGE_SHIFT < EDGE_MARGIN or ship_x + dir * DODGE_SHIFT > view_w - EDGE_MARGIN:
		dir = -dir
	_dodge_x = clampf(ship_x + dir * DODGE_SHIFT, EDGE_MARGIN, view_w - EDGE_MARGIN)
	_dodge_time_left = DODGE_HOLD


# Leave a charging UFO beam: sideways, away from the saucer's x (to the other
# side when that is off screen); replaces a running dodge
func _start_beam_escape(ship_x: float, ufo_x: float, view_w: float) -> void:
	var dir := signf(ship_x - ufo_x)
	if dir == 0.0:
		dir = 1.0 if ufo_x < view_w * 0.5 else -1.0
	var x := ufo_x + dir * BEAM_ESCAPE_X
	if x < EDGE_MARGIN or x > view_w - EDGE_MARGIN:
		x = ufo_x - dir * BEAM_ESCAPE_X
	_dodge_x = clampf(x, EDGE_MARGIN, view_w - EDGE_MARGIN)
	_dodge_time_left = DODGE_HOLD
	beam_escapes += 1


## True for a pickup the demo must not collect (the screen-clear bomb).
static func is_ignored_pickup(node: Node) -> bool:
	if node.has_method("get_pickup_type"):
		return node.get_pickup_type() in IGNORED_PICKUPS
	var script: Script = node.get_script()
	if script == null:
		return false
	for suffix in IGNORED_PICKUP_SCRIPT_SUFFIXES:
		if script.resource_path.ends_with(suffix):
			return true
	return false


## True for the weapon upgrade pickup.
static func is_weapon_pickup(node: Node) -> bool:
	if node.has_method("get_pickup_type"):
		return node.get_pickup_type() == WEAPON_PICKUP
	var script: Script = node.get_script()
	return script != null and script.resource_path.ends_with(WEAPON_PICKUP_SCRIPT_SUFFIX)


func _is_obstacle(node: Node) -> bool:
	var script: Script = node.get_script()
	if script == null:
		return false
	if not _is_obstacle_script.has(script):
		var s := script
		while s != null and s != OBSTACLE_SCRIPT:
			s = s.get_base_script()
		_is_obstacle_script[script] = s != null
	return _is_obstacle_script[script]
