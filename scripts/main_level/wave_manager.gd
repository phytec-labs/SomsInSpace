# wave_manager.gd
# Plays the current zone's waves (ZoneDefinition.waves) in order, looping.
# The longer the player stays in a zone, the higher the ramp level: delays get
# shorter and groups get extra formations (see ZoneDefinition "Difficulty Ramp").
# The Resources are never modified; effective values are computed per level.
extends Node2D

const ZoneDefinitionScript := preload("res://scripts/data/zone_definition.gd")
const WaveDefinitionScript := preload("res://scripts/data/wave_definition.gd")
const WaveGroupScript := preload("res://scripts/data/wave_group.gd")

# Timer.wait_time must be > 0 (setting 0 is rejected with an error and the
# previous value is kept), so zero/negative delays are clamped to this.
const MIN_TIMER_WAIT: float = 0.05

# ramp_level: difficulty level (time spent in the zone) when the wave started
signal wave_started(wave: WaveDefinitionScript, wave_index: int, ramp_level: int)
signal wave_completed
signal all_waves_completed

# Node references
@onready var wave_timer: Timer = $WaveTimer
@onready var enemy_timer: Timer = $EnemyTimer
@onready var formation_manager = $"../FormationManager" if has_node("../FormationManager") else null

# Wave control variables
@export var active: bool = false
@export var starting_wave: int = 0
@export var loop_waves: bool = true  # Whether to loop back to beginning after final wave
@export var debug_mode: bool = false  # Enable detailed debug logs

# Wave progression
var zone: ZoneDefinitionScript  # Current zone (set via set_zone())
var current_wave_index: int = 0
var current_group_index: int = 0
var enemies_spawned_in_group: int = 0
var zone_time: float = 0.0  # Seconds spent spawning in the current zone (drives the ramp)
var wave_in_progress: bool = false
var next_action: String = "none"  # Used to track what should happen after timer

# Keep track of recent spawn positions to avoid overlap
var recent_spawn_positions = []
var max_recent_positions = 5  # How many recent positions to remember
var min_spawn_distance = 150.0  # Minimum distance between spawn positions

func _ready() -> void:
	# Verify formation manager reference
	if not formation_manager:
		push_error("WaveManager: FormationManager node not found!")
	else:
		print("WaveManager: FormationManager found")
	
	# Verify timers
	if not wave_timer:
		push_error("WaveManager: WaveTimer node not found!")
	else:
		# Disconnect any existing connections to avoid duplicates
		if wave_timer.timeout.is_connected(_on_wave_timer_timeout):
			wave_timer.timeout.disconnect(_on_wave_timer_timeout)
		wave_timer.timeout.connect(_on_wave_timer_timeout)
	
	if not enemy_timer:
		push_error("WaveManager: EnemyTimer node not found!")
	else:
		# Disconnect any existing connections to avoid duplicates
		if enemy_timer.timeout.is_connected(_on_enemy_timer_timeout):
			enemy_timer.timeout.disconnect(_on_enemy_timer_timeout)
		enemy_timer.timeout.connect(_on_enemy_timer_timeout)
	
	# Initialize with first wave
	current_wave_index = starting_wave
	
	# Start spawning if active is set
	if active:
		start_spawning()

# Public methods
func start_spawning() -> void:
	if wave_in_progress:
		return
	
	active = true
	wave_in_progress = false
	zone_time = 0.0
	current_group_index = 0
	enemies_spawned_in_group = 0
	next_action = "start_wave"
	
	# A zone without waves (e.g. the boss zone) is a silent no-op; stay
	# active so a later set_zone() to a zone with waves resumes spawning
	if not _zone_has_waves():
		_stop_timers()
		return
	
	# Start first wave after a short delay
	_start_timer(wave_timer, 1.0)

func stop_spawning() -> void:
	active = false
	_stop_timers()

# Cancel any pending wave/group/enemy step
func _stop_timers() -> void:
	wave_in_progress = false
	next_action = "none"
	wave_timer.stop()
	enemy_timer.stop()

# True if the current zone has at least one wave to play
func _zone_has_waves() -> bool:
	return zone != null and not zone.waves.is_empty()

# Switch to a new zone (ZoneDefinition): restart from its first wave, ramp level 0
func set_zone(new_zone: ZoneDefinitionScript) -> void:
	if new_zone == null or new_zone == zone:
		return
	var is_first_zone := zone == null
	zone = new_zone
	# The very first zone honours starting_wave; later zones start at wave 0
	current_wave_index = starting_wave if is_first_zone else 0
	zone_time = 0.0
	wave_in_progress = false  # Reset the wave progress for the new zone
	_clear_recent_spawn_positions()  # Clear spawn positions when changing zones

	if debug_mode:
		print("WaveManager: Zone " + String(zone.id) + " has " + str(zone.waves.size()) + " waves")
	
	# Zone without waves (e.g. the boss zone): nothing to spawn
	if not _zone_has_waves():
		_stop_timers()
		return

	# If currently spawning, restart with new zone waves
	if active:
		next_action = "start_wave"
		wave_timer.stop()  # Ensure any running timer is stopped
		_start_timer(wave_timer, 1.0)

func _process(delta: float) -> void:
	# The tree pause stops _process, so paused time doesn't count
	if active:
		zone_time += delta

# Difficulty ramp: effective values for the current ramp level
func get_ramp_level() -> int:
	return zone.get_ramp_level(zone_time) if zone else 0

func get_delay_multiplier() -> float:
	return zone.get_delay_multiplier(get_ramp_level()) if zone else 1.0

func get_effective_count(group: WaveGroupScript) -> int:
	return group.count + get_effective_count_bonus()

func _scaled_delay(base_delay: float) -> float:
	return base_delay * get_delay_multiplier()

func _start_timer(timer: Timer, wait: float) -> void:
	timer.wait_time = maxf(wait, MIN_TIMER_WAIT)
	timer.start()

# Current wave, or null if the zone has no waves (silently) or the wave
# index is invalid (with a warning)
func _get_current_wave() -> WaveDefinitionScript:
	if not _zone_has_waves():
		return null
	if current_wave_index < 0 or current_wave_index >= zone.waves.size():
		push_warning("WaveManager: Invalid wave index " + str(current_wave_index) + " for zone " + String(zone.id))
		return null
	return zone.waves[current_wave_index]

# Wave control methods
func start_wave() -> void:
	if not active:
		if debug_mode:
			print("WaveManager: Cannot start wave - not active")
		return
	
	if wave_in_progress:
		if debug_mode:
			print("WaveManager: Cannot start wave - wave already in progress")
		return
	
	# Zones without waves (e.g. the boss zone) spawn nothing
	if not _zone_has_waves():
		return
	
	# Wrap around if we've gone past the end and looping is enabled
	if current_wave_index >= zone.waves.size():
		if loop_waves:
			current_wave_index = 0
			if debug_mode:
				print("WaveManager: Zone %s wrapped at ramp level %d (delay x%.2f, +%d per group)" % [
					zone.id, get_ramp_level(), get_delay_multiplier(), get_effective_count_bonus()])
		else:
			emit_signal("all_waves_completed")
			return
	
	# Get current wave data
	var wave_data := _get_current_wave()
	if wave_data == null:
		return
	wave_in_progress = true
	current_group_index = 0
	enemies_spawned_in_group = 0
	
	# Start the first group in the wave
	wave_started.emit(wave_data, current_wave_index, get_ramp_level())
	spawn_formation_group()

func get_effective_count_bonus() -> int:
	return zone.get_count_bonus(get_ramp_level()) if zone else 0

func spawn_formation_group() -> void:
	if not wave_in_progress:
		if debug_mode:
			print("WaveManager: Cannot spawn formation group - wave not in progress")
		return
	
	var wave_data := _get_current_wave()
	if wave_data == null:
		return
	
	# Check if we've completed all groups in this wave
	if current_group_index >= wave_data.groups.size():
		complete_wave()
		return
	
	# Get current group data
	var group: WaveGroupScript = wave_data.groups[current_group_index]
	enemies_spawned_in_group = 0
	
	# Start spawning enemies in this group
	var enemy_delay := _scaled_delay(group.enemy_delay)
	next_action = "wait_for_next_enemy"
	_start_timer(enemy_timer, enemy_delay)
	
	if debug_mode:
		print("WaveManager: First enemy will spawn in " + str(enemy_delay) + " seconds")

func spawn_enemy_in_group() -> void:
	if not wave_in_progress:
		if debug_mode:
			print("WaveManager: Cannot spawn enemy - wave not in progress")
		return
	
	# Additional validations
	var wave_data := _get_current_wave()
	if wave_data == null:
		return
	
	if current_group_index >= wave_data.groups.size():
		push_warning("WaveManager: Invalid group index: " + str(current_group_index))
		return
		
	var group: WaveGroupScript = wave_data.groups[current_group_index]
	var group_count := get_effective_count(group)
	
	# Check if we've spawned all enemies in this group
	if enemies_spawned_in_group >= group_count:
		# Move to next group after delay
		current_group_index += 1
		next_action = "wait_for_next_group"
		wave_timer.stop() # Ensure timer is stopped before starting again
		_start_timer(wave_timer, _scaled_delay(group.delay))
		return
	
	# Get a random spawn position from the allowed positions for this group
	var spawn_position_type := "top"
	if not group.spawn_positions.is_empty():
		spawn_position_type = String(group.spawn_positions[randi() % group.spawn_positions.size()])
	var spawn_position = _get_spawn_position(spawn_position_type)
	
	# Create the formation using formation manager
	if formation_manager:
		var formation_objects = formation_manager.create_formation(
			group.formation,
			spawn_position,
			Callable(get_parent(), "spawn_obstacle")
		)
		
		if debug_mode:
			if formation_objects.size() > 0:
				print("WaveManager: Created formation with " + str(formation_objects.size()) + " enemies")
			else:
				push_warning("WaveManager: Formation creation failed - no objects returned")
	else:
		push_warning("WaveManager: Cannot create formation - formation_manager is null")
	
	enemies_spawned_in_group += 1
	
	# Continue spawning if more enemies in this group
	if enemies_spawned_in_group < group_count:
		next_action = "wait_for_next_enemy"
		enemy_timer.stop() # Ensure timer is stopped before starting again
		_start_timer(enemy_timer, _scaled_delay(group.enemy_delay))
	else:
		# We need to explicitly check for moving to the next group
		# This duplication is intentional for robustness
		current_group_index += 1
		
		# Check if this was the last group
		if current_group_index >= wave_data.groups.size():
			complete_wave()
		else:
			# Set up for next group
			next_action = "wait_for_next_group"
			wave_timer.stop() # Ensure timer is stopped before starting again
			_start_timer(wave_timer, _scaled_delay(group.delay))

func complete_wave() -> void:
	# Wave completed, prepare for next wave
	wave_in_progress = false
	
	# Ensure we've got valid data
	var wave_data := _get_current_wave()
	if wave_data == null:
		if not _zone_has_waves():
			_stop_timers()
			return
		# Reset to a valid state
		current_wave_index = 0
		next_action = "start_wave"
		_start_timer(wave_timer, 2.0)
		return
	
	# Get completion delay before incrementing wave index
	var completion_delay := _scaled_delay(wave_data.completion_delay)
	
	# Increment wave index
	current_wave_index += 1
	
	# Emit completion signal
	emit_signal("wave_completed")
	
	# Start next wave after completion delay
	next_action = "start_wave"
	wave_timer.stop() # Ensure timer is stopped before starting again
	_start_timer(wave_timer, completion_delay)

# Timer callbacks
func _on_wave_timer_timeout() -> void:
	if next_action == "start_wave":
		start_wave()
	elif next_action == "wait_for_next_group":
		spawn_formation_group()
	else:
		# Default behavior
		if active and not wave_in_progress:
			start_wave()
		elif wave_in_progress:
			spawn_formation_group()

func _on_enemy_timer_timeout() -> void:
	if next_action == "wait_for_next_enemy":
		spawn_enemy_in_group()
	else:
		# Default behavior
		if wave_in_progress:
			spawn_enemy_in_group()

# Spawn position generation methods
func _get_spawn_position(position_type: String) -> Vector2:
	match position_type:
		"top":
			return _get_top_spawn_position()
		"left":
			return _get_left_spawn_position()
		"right":
			return _get_right_spawn_position()
		"bottom":
			return _get_bottom_spawn_position()
		_:
			# Default to top
			return _get_top_spawn_position()

# Modified top spawn position with more variation
func _get_top_spawn_position() -> Vector2:
	var viewport_rect = get_viewport().get_visible_rect()
	var margin = 50
	var screen_width = viewport_rect.size.x
	
	# Divide the screen into 5 segments
	var segment_width = (screen_width - 2*margin) / 5.0
	
	# Try to find a good position that isn't too close to recent positions
	var position_attempts = 0
	var max_attempts = 10
	var final_position
	var found_good_position = false
	
	while position_attempts < max_attempts and not found_good_position:
		# Choose a random segment
		var segment = randi() % 5
		
		# Calculate x position within that segment plus some randomness
		var base_x = margin + segment * segment_width
		var x_pos = base_x + randf_range(0, segment_width)
		
		# Add some variation to y position
		var y_pos = randf_range(-150, -80)  # Different heights above screen
		
		final_position = Vector2(x_pos, y_pos)
		
		# Check if the position is far enough from recent positions
		found_good_position = true
		for recent_pos in recent_spawn_positions:
			if final_position.distance_to(recent_pos) < min_spawn_distance:
				found_good_position = false
				break
		
		position_attempts += 1
	
	# If we couldn't find a good position after max attempts, just use the last one
	if not found_good_position:
		final_position = Vector2(randf_range(margin, screen_width - margin), -100)
	
	# Add to recent positions and remove oldest if needed
	recent_spawn_positions.append(final_position)
	if recent_spawn_positions.size() > max_recent_positions:
		recent_spawn_positions.pop_front()
	
	return final_position

# Modified left spawn position with more variation
func _get_left_spawn_position() -> Vector2:
	var viewport_rect = get_viewport().get_visible_rect()
	var margin = 50
	var screen_width = viewport_rect.size.x
	
	# Ensure y position is above the viewable area
	var y_pos = randf_range(-150, -20)  # Higher up and offscreen
	
	# Add some variation to x position
	var x_pos = randf_range(-150, -80)  # Different distances left of screen
	
	var final_position = Vector2(x_pos, y_pos)
	
	# Try to keep distance from recent positions
	var closest_recent = 9999.0
	for recent_pos in recent_spawn_positions:
		var dist = final_position.distance_to(recent_pos)
		closest_recent = min(closest_recent, dist)
	
	# If too close to a recent position, adjust slightly
	if closest_recent < min_spawn_distance and not recent_spawn_positions.is_empty():
		# Move it slightly more off-screen
		x_pos -= 50
		y_pos -= 20
		final_position = Vector2(x_pos, y_pos)
	
	# Add to recent positions and remove oldest if needed
	recent_spawn_positions.append(final_position)
	if recent_spawn_positions.size() > max_recent_positions:
		recent_spawn_positions.pop_front()
	
	return final_position

# Modified right spawn position to ensure offscreen spawning
func _get_right_spawn_position() -> Vector2:
	var viewport_rect = get_viewport().get_visible_rect()
	var screen_width = viewport_rect.size.x
	
	# Ensure y position is above the viewable area
	var y_pos = randf_range(-150, -20)  # Higher up and offscreen
	
	# Add some variation to x position
	var x_pos = screen_width + randf_range(80, 150)  # Different distances right of screen
	
	var final_position = Vector2(x_pos, y_pos)
	
	# Try to keep distance from recent positions
	var closest_recent = 9999.0
	for recent_pos in recent_spawn_positions:
		var dist = final_position.distance_to(recent_pos)
		closest_recent = min(closest_recent, dist)
	
	# If too close to a recent position, adjust slightly
	if closest_recent < min_spawn_distance and not recent_spawn_positions.is_empty():
		# Move it slightly more off-screen
		x_pos += 50
		y_pos -= 20
		final_position = Vector2(x_pos, y_pos)
	
	# Add to recent positions and remove oldest if needed
	recent_spawn_positions.append(final_position)
	if recent_spawn_positions.size() > max_recent_positions:
		recent_spawn_positions.pop_front()
	
	return final_position

# Clear the recent spawn positions (call this when changing zones)
func _clear_recent_spawn_positions() -> void:
	recent_spawn_positions.clear()

func _get_bottom_spawn_position() -> Vector2:
	var viewport_rect = get_viewport().get_visible_rect()
	var margin = 50
	var x_pos = randf_range(margin, viewport_rect.size.x - margin)
	var y_pos = viewport_rect.size.y + 100  # Below screen
	return Vector2(x_pos, y_pos)
