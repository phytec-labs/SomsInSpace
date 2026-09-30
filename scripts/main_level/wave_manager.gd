# wave_manager.gd
# Sequencer for the current zone's waves (ZoneDefinition.waves), in a fixed
# order every run; the only per-run variation is the left/right mirror of
# groups that allow it (see docs/WAVE_DESIGN.md).
#
# For each WaveGroup of a wave:
#   1. wait for a free formation slot (the zone's max_formations_on_screen,
#      or GameConfig.max_formations_on_screen when the zone leaves it at 0)
#   2. telegraph: show a marker at the entry point, wait telegraph_seconds
#      (scaled by the ramp's beat multiplier, min 0.3 s)
#   3. spawn the formation (FormationManager) or scene_override singles
#   4. release the next group: ON_CLEAR waits until this group is cleared
#      (dead / off screen) plus beat_after; AFTER_DELAY waits `delay`
# After the last group, the wave waits until every group it spawned is
# cleared (except scene_override singles released AFTER_DELAY, which keep
# flying on their own), then completion_delay, then the next wave. Past the last wave it
# loops (one_shot groups already spawned this visit are skipped).
#
# Difficulty ramp: the longer the player stays in a zone, the higher the ramp
# level; it multiplies formation speeds up and beats / delays down (see
# ZoneDefinition "Difficulty Ramp"). Counts never change. The Resources are
# never modified.
#
# Pause-safe: a single state machine advanced from _process() delta.
extends Node2D

const ZoneDefinitionScript := preload("res://scripts/data/zone_definition.gd")
const WaveDefinitionScript := preload("res://scripts/data/wave_definition.gd")
const WaveGroupScript := preload("res://scripts/data/wave_group.gd")
const TELEGRAPH_SCENE := preload("res://scenes/effects/spawn_telegraph.tscn")

# Delay before the first wave of a zone (also after a zone change)
const ZONE_START_DELAY: float = 1.0
# Retry interval when a spawn produced nothing (obstacle cap)
const CAP_RETRY_DELAY: float = 0.25
# Telegraph marker inset from the screen edge (px)
const TELEGRAPH_INSET: float = 44.0
# Fallbacks when no GameConfig is available
const DEFAULT_MAX_FORMATIONS: int = 3
const DEFAULT_TELEGRAPH_SECONDS: float = 0.5
const MIN_TELEGRAPH_SECONDS: float = 0.3

# ramp_level: difficulty level (time spent in the zone) when the wave started
signal wave_started(wave: WaveDefinitionScript, wave_index: int, ramp_level: int)
signal wave_completed
# A group was spawned (formation_id = -1 never emitted); for tests / debugging
signal group_spawned(group: WaveGroupScript, formation_id: int, mirrored: bool)

enum State {
	IDLE,         # Not spawning / zone without waves
	WAIT,         # Counting down _timer, then _after_wait
	SLOT,         # Waiting for a free formation slot
	TELEGRAPH,    # Marker showing; spawn when _timer runs out
	CLEAR,        # Waiting for _wait_formation to be cleared
	WAVE_CLEAR,   # Waiting for every formation of the wave to be cleared
}

@onready var formation_manager = $"../FormationManager" if has_node("../FormationManager") else null

@export var active: bool = false
@export var starting_wave: int = 0
@export var debug_mode: bool = false  # Enable detailed debug logs

# Wave progression
var zone: ZoneDefinitionScript  # Current zone (set via set_zone())
var current_wave_index: int = 0
var current_group_index: int = 0
var zone_time: float = 0.0  # Seconds spent spawning in the current zone (drives the ramp)
var rng := RandomNumberGenerator.new()  # Mirror rolls (tests may seed it)

var _state: State = State.IDLE
var _timer: float = 0.0
var _after_wait: Callable = Callable()
var _group: WaveGroupScript = null   # Group being released
var _mirrored: bool = false          # Mirror roll for _group
var _wait_formation: int = -1        # ON_CLEAR: formation being waited on
var _wave_formations: Array[int] = []  # Formations spawned by the current wave
# WaveGroups with one_shot that already spawned something during the current
# zone visit (used as a set; cleared by set_zone())
var _spent_one_shot_groups: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	if not formation_manager:
		push_error("WaveManager: FormationManager node not found!")
	current_wave_index = starting_wave
	if active:
		start_spawning()

# --- Public API ---

func start_spawning() -> void:
	active = true
	zone_time = 0.0
	_begin_zone()

func stop_spawning() -> void:
	active = false
	_set_idle()

# Switch to a new zone (ZoneDefinition): restart from its first wave, ramp
# level 0. Formations already flying keep going.
func set_zone(new_zone: ZoneDefinitionScript) -> void:
	if new_zone == null or new_zone == zone:
		return
	var is_first_zone := zone == null
	zone = new_zone
	# The very first zone honours starting_wave; later zones start at wave 0
	current_wave_index = starting_wave if is_first_zone else 0
	zone_time = 0.0
	_spent_one_shot_groups.clear()  # New zone visit: one-shot groups may spawn again
	if debug_mode:
		print("WaveManager: Zone %s has %d waves" % [zone.id, zone.waves.size()])
	if active:
		_begin_zone()
	else:
		_set_idle()

# Difficulty ramp level for the time spent in the current zone (HUD threat)
func get_ramp_level() -> int:
	return zone.get_ramp_level(zone_time) if zone else 0

func get_speed_multiplier() -> float:
	return zone.get_speed_multiplier(get_ramp_level()) if zone else 1.0

func get_beat_multiplier() -> float:
	return zone.get_beat_multiplier(get_ramp_level()) if zone else 1.0

# True for a one_shot group that already spawned during this zone visit
func is_group_spent(group: WaveGroupScript) -> bool:
	return group.one_shot and _spent_one_shot_groups.has(group)

# State name (tests / debugging)
func get_state_name() -> String:
	return State.keys()[_state]

# --- State machine ---

func _process(delta: float) -> void:
	# The tree pause stops _process, so paused time doesn't count
	if not active:
		return
	zone_time += delta

	match _state:
		State.WAIT:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE
				var next := _after_wait
				_after_wait = Callable()
				if next.is_valid():
					next.call()
		State.SLOT:
			if _has_free_slot():
				_begin_group_spawn()
		State.TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				_spawn_group()
		State.CLEAR:
			if _is_cleared(_wait_formation):
				_wait(_group.beat_after * get_beat_multiplier(), _next_group)
		State.WAVE_CLEAR:
			if _wave_cleared():
				var wave := _get_current_wave()
				var completion := wave.completion_delay if wave else 1.0
				current_wave_index += 1
				wave_completed.emit()
				_wait(completion * get_beat_multiplier(), _start_wave)

func _set_idle() -> void:
	_state = State.IDLE
	_timer = 0.0
	_after_wait = Callable()
	_group = null
	_wait_formation = -1
	_wave_formations.clear()

# (Re)start the current zone's sequence after a short delay
func _begin_zone() -> void:
	_set_idle()
	if not _zone_has_waves():
		return  # e.g. the boss zone: silent, but stays active for later zones
	_wait(ZONE_START_DELAY, _start_wave)

func _wait(seconds: float, then: Callable) -> void:
	_state = State.WAIT
	_timer = maxf(seconds, 0.0)
	_after_wait = then

func _zone_has_waves() -> bool:
	return zone != null and not zone.waves.is_empty()

func _get_current_wave() -> WaveDefinitionScript:
	if not _zone_has_waves() or current_wave_index < 0 or current_wave_index >= zone.waves.size():
		return null
	return zone.waves[current_wave_index]

func _start_wave() -> void:
	if not active or not _zone_has_waves():
		_set_idle()
		return
	if current_wave_index < 0 or current_wave_index >= zone.waves.size():
		current_wave_index = 0
		if debug_mode:
			print("WaveManager: Zone %s looped at ramp level %d (speed x%.2f, beats x%.2f)" % [
				zone.id, get_ramp_level(), get_speed_multiplier(), get_beat_multiplier()])
	var wave := _get_current_wave()
	current_group_index = 0
	_wave_formations.clear()
	wave_started.emit(wave, current_wave_index, get_ramp_level())
	if debug_mode:
		print("WaveManager: wave %d '%s' (ramp %d)" % [current_wave_index, wave.name, get_ramp_level()])
	_prepare_group()

# Pick the next unspent group of the wave (or finish the wave)
func _prepare_group() -> void:
	var wave := _get_current_wave()
	if wave == null:
		_set_idle()
		return
	while current_group_index < wave.groups.size() \
			and (wave.groups[current_group_index] == null or is_group_spent(wave.groups[current_group_index])):
		current_group_index += 1
	if current_group_index >= wave.groups.size():
		_state = State.WAVE_CLEAR
		return

	_group = wave.groups[current_group_index]
	_mirrored = _group.force_mirror or (_group.mirror_allowed and rng.randf() < 0.5)
	if _has_free_slot():
		_begin_group_spawn()
	else:
		_state = State.SLOT

func _next_group() -> void:
	current_group_index += 1
	_prepare_group()

# Slot is free: telegraph (if asked) then spawn
func _begin_group_spawn() -> void:
	if _group.telegraph:
		_show_telegraph(_group, _mirrored)
		_state = State.TELEGRAPH
		_timer = _get_telegraph_seconds()
	else:
		_spawn_group()

func _spawn_group() -> void:
	# A slot may have been taken meanwhile (AFTER_DELAY overlaps): wait for
	# one again (the group is telegraphed again once it frees up)
	if not _has_free_slot():
		_state = State.SLOT
		return

	var formation_id := -1
	if formation_manager:
		if _group.scene_override:
			formation_id = formation_manager.create_single_group(_group, _mirrored)
		else:
			formation_id = formation_manager.create_path_formation(_group, zone, _mirrored, get_speed_multiplier())

	if formation_id < 0:
		# Nothing spawned (obstacle cap or bad data): retry shortly
		if debug_mode:
			print("WaveManager: group %s spawned nothing; retrying" % _group.describe())
		_wait(CAP_RETRY_DELAY, _spawn_group_retry)
		return

	if _group.one_shot:
		_spent_one_shot_groups[_group] = true
	if _blocks_wave_completion(_group):
		_wave_formations.append(formation_id)
	group_spawned.emit(_group, formation_id, _mirrored)
	if debug_mode:
		print("WaveManager: spawned %s (mirrored %s) as formation %d" % [_group.describe(), _mirrored, formation_id])

	if _group.release == WaveGroupScript.Release.AFTER_DELAY:
		_wait(_group.delay * get_beat_multiplier(), _next_group)
	else:
		_wait_formation = formation_id
		_state = State.CLEAR

# Formation groups always hold the wave until cleared. A scene_override
# single released AFTER_DELAY (the UFO escort lead) does not: it keeps flying
# on its own while the wave moves on. ON_CLEAR singles (the blimp mini-boss
# beat) still block.
func _blocks_wave_completion(group: WaveGroupScript) -> bool:
	return not (group.scene_override and group.release == WaveGroupScript.Release.AFTER_DELAY)

func _spawn_group_retry() -> void:
	if _group == null:
		return
	if _has_free_slot():
		_spawn_group()
	else:
		_state = State.SLOT

func _has_free_slot() -> bool:
	if formation_manager == null:
		return true
	return formation_manager.get_formations_on_screen() < _get_max_formations()

func _is_cleared(formation_id: int) -> bool:
	return formation_manager == null or formation_manager.is_formation_cleared(formation_id)

func _wave_cleared() -> bool:
	for formation_id in _wave_formations:
		if not _is_cleared(formation_id):
			return false
	return true

func _get_config() -> Resource:
	var spawn_manager = get_parent()
	return spawn_manager.get("config") if spawn_manager else null

# Formation slots for the current zone: its own max_formations_on_screen if
# set (> 0), else GameConfig.max_formations_on_screen
func _get_max_formations() -> int:
	if zone and zone.max_formations_on_screen > 0:
		return zone.max_formations_on_screen
	var config = _get_config()
	return config.max_formations_on_screen if config else DEFAULT_MAX_FORMATIONS

# GameConfig.telegraph_seconds, shortened by the ramp like the beats (but
# never below MIN_TELEGRAPH_SECONDS so the warning stays readable)
func _get_telegraph_seconds() -> float:
	var config = _get_config()
	var seconds: float = config.telegraph_seconds if config else DEFAULT_TELEGRAPH_SECONDS
	if seconds <= 0.0:
		return 0.0
	return maxf(seconds * get_beat_multiplier(), minf(seconds, MIN_TELEGRAPH_SECONDS))

# Marker at the group's entry point, pulled onto the screen edge, pointing
# along the path
func _show_telegraph(group: WaveGroupScript, mirrored: bool) -> void:
	if formation_manager == null:
		return
	var start: Vector2 = formation_manager.get_path_start(group.path, mirrored)
	var ahead: Vector2 = formation_manager.get_path_point(group.path, mirrored, 160.0)
	var size := get_viewport_rect().size
	var at := Vector2(clampf(start.x, TELEGRAPH_INSET, size.x - TELEGRAPH_INSET),
		clampf(start.y, TELEGRAPH_INSET, size.y - TELEGRAPH_INSET))
	var marker = ObjectPool.acquire(TELEGRAPH_SCENE, get_parent())
	marker.start(at, _get_telegraph_seconds(), ahead - start)
