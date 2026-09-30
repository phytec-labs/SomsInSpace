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
# to reach the ship. Scene scans run every SCAN_INTERVAL frames and only read
# the spawn manager's children and the `enemy_projectile` group.
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
## Enemy shot dodge: horizontal trigger distance, look-ahead above the ship,
## sideways shift, and how long a dodge is held
const SHOT_DODGE_X := 90.0
const SHOT_LOOK_AHEAD := 220.0
const DODGE_SHIFT := 120.0
const DODGE_HOLD := 0.35
## Enemies closer than this (vertically) are dodged instead of tracked
const RAM_DISTANCE := 230.0
## Keep the target this far from the screen edges
const EDGE_MARGIN := 60.0
## Ignored pickups (bomb) are kept at least this far sideways from the ship
## target while they are between AVOID_ABOVE px above and AVOID_BELOW px below
## the ship
const AVOID_X := 130.0
const AVOID_ABOVE := 320.0
const AVOID_BELOW := 80.0

var level: Node
var player: Node2D
var spawn_manager: Node

var _time: float = 0.0
var _frame: int = 0
var _track_x: float = NAN
var _dodge_x: float = 0.0
var _dodge_time_left: float = 0.0
# x of ignored pickups (bombs) near the ship's height, refreshed by _scan()
var _avoid_xs: Array[float] = []
# Script -> extends obstacle.gd (enemies are dodged when close; pickups aren't)
var _is_obstacle_script: Dictionary = {}


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
		x = lerpf(sweep_x, _track_x, TRACK_WEIGHT)
	if _dodge_time_left > 0.0:
		x = _dodge_x
	x = _avoid_ignored_pickups(x, player.global_position.x, view.x)
	x = clampf(x, EDGE_MARGIN, view.x - EDGE_MARGIN)
	# Set directly (not through update_target_position), so this is already
	# the final ship position: no touch_offset to subtract
	var y := view.y * CRUISE_Y_FRACTION + sin(_time * BOB_SPEED) * BOB_AMPLITUDE

	player.set("target_position", Vector2(x, y))
	player.set("is_touch_active", true)
	player.set("is_firing", true)


func _scan() -> void:
	var ship: Vector2 = player.global_position
	_track_x = NAN
	_avoid_xs.clear()

	# Nearest active enemy (or wanted pickup) above the ship is tracked; an
	# enemy (or an ignored pickup) about to reach the ship is dodged
	var best_dist := INF
	if is_instance_valid(spawn_manager):
		for child in spawn_manager.get_children():
			if not (child is Node2D) or not child.visible or not child.get("is_active"):
				continue
			var pos: Vector2 = child.global_position
			var above := ship.y - pos.y
			if is_ignored_pickup(child):
				# Never steer toward it; keep clear while it passes the ship
				if above > -AVOID_BELOW and above < AVOID_ABOVE:
					_avoid_xs.append(pos.x)
				continue
			if above < -40.0:
				continue  # Already below the ship
			if above < RAM_DISTANCE and absf(pos.x - ship.x) < DODGE_SHIFT and _is_obstacle(child):
				_start_dodge(ship.x, pos.x)
				continue
			var dist := ship.distance_squared_to(pos)
			if dist < best_dist:
				best_dist = dist
				_track_x = pos.x

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
