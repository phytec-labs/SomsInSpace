# wave_manager.gd
extends Node2D

signal wave_started(wave_data)
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
var current_wave_index: int = 0
var current_group_index: int = 0
var enemies_spawned_in_group: int = 0
var wave_in_progress: bool = false
var current_zone: String = "ground"
var next_action: String = "none"  # Used to track what should happen after timer

# Keep track of recent spawn positions to avoid overlap
var recent_spawn_positions = []
var max_recent_positions = 5  # How many recent positions to remember
var min_spawn_distance = 150.0  # Minimum distance between spawn positions

# Wave definitions
# Each wave contains multiple groups
# Each group contains a formation type and count
var waves = {
	"ground": [
		{
			"name": "Ground Tutorial",
			"groups": [
				{
					"formation": "line",
					"count": 1,
					"delay": 1.0,
					"enemy_delay": 0.5,
					"spawn_positions": ["top"]
				},
				{
					"formation": "line",
					"count": 2,
					"delay": 2.0,
					"enemy_delay": 0.5,
					"spawn_positions": ["top"]
				}
			],
			"completion_delay": 3.0
		},
		{
			"name": "Ground Easy",
			"groups": [
				{
					"formation": "line",
					"count": 3,
					"delay": 0.8,
					"enemy_delay": 0.4,
					"spawn_positions": ["top"]
				},
				{
					"formation": "v_shape",
					"count": 1,
					"delay": 1.5,
					"enemy_delay": 0.3,
					"spawn_positions": ["top"]
				}
			],
			"completion_delay": 2.5
		}
	],
	"atmosphere": [
		{
			"name": "Atmosphere Introduction",
			"groups": [
				{
					"formation": "v_shape",
					"count": 2,
					"delay": 0.8,
					"enemy_delay": 0.3,
					"spawn_positions": ["top"]
				},
				{
					"formation": "line",
					"count": 1,
					"delay": 1.0,
					"enemy_delay": 0.2,
					"spawn_positions": ["left", "right"]
				}
			],
			"completion_delay": 2.0
		},
		{
			"name": "Atmosphere Challenge",
			"groups": [
				{
					"formation": "line",
					"count": 1,
					"delay": 0.5,
					"enemy_delay": 0.3,
					"spawn_positions": ["left"]
				},
				{
					"formation": "line",
					"count": 1,
					"delay": 0.5,
					"enemy_delay": 0.3,
					"spawn_positions": ["right"]
				},
				{
					"formation": "v_shape",
					"count": 1,
					"delay": 1.5,
					"enemy_delay": 0.2,
					"spawn_positions": ["top"]
				}
			],
			"completion_delay": 2.0
		}
	],
	"upper_atmosphere": [
		{
			"name": "Upper Atmosphere Intro",
			"groups": [
				{
					"formation": "v_shape",
					"count": 1,
					"delay": 0.0,
					"enemy_delay": 0.2,
					"spawn_positions": ["left", "right"]
				},
				{
					"formation": "diagonal",
					"count": 2,
					"delay": 1.0,
					"enemy_delay": 0.15,
					"spawn_positions": ["top"]
				}
			],
			"completion_delay": 1.5
		},
		{
			"name": "Upper Atmosphere Battle",
			"groups": [
				{
					"formation": "square",
					"count": 1,
					"delay": 0.0,
					"enemy_delay": 0.2,
					"spawn_positions": ["top"]
				},
				{
					"formation": "v_shape",
					"count": 1,
					"delay": 1.0,
					"enemy_delay": 0.15,
					"spawn_positions": ["left"]
				},
				{
					"formation": "v_shape",
					"count": 1,
					"delay": 1.0,
					"enemy_delay": 0.15,
					"spawn_positions": ["right"]
				}
			],
			"completion_delay": 1.5
		}
	],
	"space": [
		{
			"name": "Space Assault",
			"groups": [
				{
					"formation": "circle",
					"count": 1,
					"delay": 0.0,
					"enemy_delay": 0.1,
					"spawn_positions": ["top"]
				},
				{
					"formation": "square",
					"count": 1,
					"delay": 1.5,
					"enemy_delay": 0.1,
					"spawn_positions": ["left", "right"]
				},
				{
					"formation": "diagonal",
					"count": 2,
					"delay": 1.0,
					"enemy_delay": 0.1,
					"spawn_positions": ["top"]
				}
			],
			"completion_delay": 1.0
		},
		{
			"name": "Space Final",
			"groups": [
				{
					"formation": "circle",
					"count": 1,
					"delay": 0.0,
					"enemy_delay": 0.08,
					"spawn_positions": ["top"]
				},
				{
					"formation": "v_shape",
					"count": 1,
					"delay": 0.5,
					"enemy_delay": 0.08,
					"spawn_positions": ["left"]
				},
				{
					"formation": "v_shape",
					"count": 1,
					"delay": 0.5,
					"enemy_delay": 0.08,
					"spawn_positions": ["right"]
				},
				{
					"formation": "square",
					"count": 1,
					"delay": 1.0,
					"enemy_delay": 0.05,
					"spawn_positions": ["top"]
				}
			],
			"completion_delay": 1.0
		}
	]
}

# Formation type mapping
var formation_type_map = {
	"line": 0,      # LINE in FormationType enum
	"v_shape": 1,   # V_SHAPE in FormationType enum
	"square": 2,    # SQUARE in FormationType enum
	"diagonal": 3,  # DIAGONAL in FormationType enum
	"wave": 4,      # WAVE in FormationType enum
	"circle": 5,    # CIRCLE in FormationType enum
	"random": 6     # RANDOM in FormationType enum
}

# Spawn position map (these will be used to generate positions)
var spawn_position_map = {
	"top": Callable(self, "_get_top_spawn_position"),
	"left": Callable(self, "_get_left_spawn_position"),
	"right": Callable(self, "_get_right_spawn_position"),
	"bottom": Callable(self, "_get_bottom_spawn_position")
}

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
		#print("WaveManager: WaveTimer connected")
	
	if not enemy_timer:
		push_error("WaveManager: EnemyTimer node not found!")
	else:
		# Disconnect any existing connections to avoid duplicates
		if enemy_timer.timeout.is_connected(_on_enemy_timer_timeout):
			enemy_timer.timeout.disconnect(_on_enemy_timer_timeout)
		enemy_timer.timeout.connect(_on_enemy_timer_timeout)
		#print("WaveManager: EnemyTimer connected")
	
	# Initialize with first wave
	current_wave_index = starting_wave
	
	# Log available waves
	if debug_mode:
		for zone in waves.keys():
			print("WaveManager: Zone " + zone + " has " + str(waves[zone].size()) + " waves")
	
	# Start spawning if active is set
	if active:
		start_spawning()

# Called every frame. Add process code to handle wave progression
func _process(delta: float) -> void:
	# Check if any timers have been stopped unexpectedly
	if next_action == "wait_for_next_group" and not wave_timer.is_stopped() and not wave_timer.time_left > 0:
		if debug_mode:
			print("WaveManager: Wave timer got stuck, restarting next group...")
		wave_timer.stop()
		spawn_formation_group()
	
	elif next_action == "wait_for_next_enemy" and not enemy_timer.is_stopped() and not enemy_timer.time_left > 0:
		if debug_mode:
			print("WaveManager: Enemy timer got stuck, restarting enemy spawn...")
		enemy_timer.stop()
		spawn_enemy_in_group()

# Public methods
func start_spawning() -> void:
	if wave_in_progress:
		return
	
	active = true
	wave_in_progress = false
	current_group_index = 0
	enemies_spawned_in_group = 0
	next_action = "start_wave"
	
	# Start first wave after a short delay
	wave_timer.wait_time = 1.0
	wave_timer.start()

func stop_spawning() -> void:
	active = false
	wave_in_progress = false
	next_action = "none"
	wave_timer.stop()
	enemy_timer.stop()

func set_zone(zone: String) -> void:
	# Update the zone and reset wave index
	if zone != current_zone:
		current_zone = zone
		current_wave_index = 0
		wave_in_progress = false  # Reset the wave progress for the new zone
		_clear_recent_spawn_positions()  # Clear spawn positions when changing zones
		
		# If currently spawning, restart with new zone waves
		if active:
			next_action = "start_wave"
			wave_timer.stop()  # Ensure any running timer is stopped
			wave_timer.wait_time = 1.0
			wave_timer.start()

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
	
	if not waves.has(current_zone):
		push_warning("WaveManager: No waves defined for zone: " + current_zone)
		return
		
	if waves[current_zone].size() == 0:
		push_warning("WaveManager: Zone " + current_zone + " has no waves defined")
		return
	
	# Wrap around if we've gone past the end and looping is enabled
	if current_wave_index >= waves[current_zone].size():
		if loop_waves:
			current_wave_index = 0
		else:
			emit_signal("all_waves_completed")
			return
	
	# Get current wave data
	var wave_data = waves[current_zone][current_wave_index]
	wave_in_progress = true
	current_group_index = 0
	enemies_spawned_in_group = 0
	
	# Start the first group in the wave
	emit_signal("wave_started", wave_data)
	spawn_formation_group()

func spawn_formation_group() -> void:
	if not wave_in_progress:
		if debug_mode:
			print("WaveManager: Cannot spawn formation group - wave not in progress")
		return
	
	# Validate that we have waves for this zone
	if not waves.has(current_zone):
		push_warning("WaveManager: No waves defined for zone: " + current_zone)
		return
	
	# Validate that the wave index is valid
	if current_wave_index >= waves[current_zone].size():
		push_warning("WaveManager: Invalid wave index " + str(current_wave_index) + " for zone " + current_zone)
		return
		
	var wave_data = waves[current_zone][current_wave_index]
	
	# Check if we've completed all groups in this wave
	if current_group_index >= wave_data.groups.size():
		complete_wave()
		return
	
	# Get current group data
	var group = wave_data.groups[current_group_index]
	enemies_spawned_in_group = 0
	
	# Start spawning enemies in this group
	next_action = "wait_for_next_enemy"
	enemy_timer.wait_time = group.enemy_delay
	enemy_timer.start()
	
	if debug_mode:
		print("WaveManager: First enemy will spawn in " + str(group.enemy_delay) + " seconds")

func spawn_enemy_in_group() -> void:
	if not wave_in_progress:
		if debug_mode:
			print("WaveManager: Cannot spawn enemy - wave not in progress")
		return
	
	# Additional validations
	if not waves.has(current_zone) or current_wave_index >= waves[current_zone].size():
		push_warning("WaveManager: Invalid wave data access attempt")
		return
		
	var wave_data = waves[current_zone][current_wave_index]
	
	if current_group_index >= wave_data.groups.size():
		push_warning("WaveManager: Invalid group index: " + str(current_group_index))
		return
		
	var group = wave_data.groups[current_group_index]
	
	# Check if we've spawned all enemies in this group
	if enemies_spawned_in_group >= group.count:
		# Move to next group after delay
		current_group_index += 1
		next_action = "wait_for_next_group"
		wave_timer.stop() # Ensure timer is stopped before starting again
		wave_timer.wait_time = group.delay
		wave_timer.start()
		return
	
	# Spawn a formation based on the group definition
	var formation_type_enum = formation_type_map[group.formation]
	
	# Get a random spawn position from the allowed positions for this group
	var spawn_position_type = group.spawn_positions[randi() % group.spawn_positions.size()]
	var spawn_position = _get_spawn_position(spawn_position_type)
	
	# Create the formation using formation manager
	if formation_manager:
		var formation_objects = formation_manager.create_formation(
			formation_type_enum,
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
	if enemies_spawned_in_group < group.count:
		next_action = "wait_for_next_enemy"
		enemy_timer.stop() # Ensure timer is stopped before starting again
		enemy_timer.wait_time = group.enemy_delay
		enemy_timer.start()
	else:
		# We need to explicitly check for moving to the next group
		# This duplication is intentional for robustness
		current_group_index += 1
		
		# Check if this was the last group
		if current_group_index >= wave_data.groups.size():
			complete_wave()
		else:
			# Set up for next group
			var delay = group.delay
			next_action = "wait_for_next_group"
			wave_timer.stop() # Ensure timer is stopped before starting again
			wave_timer.wait_time = delay
			wave_timer.start()

func complete_wave() -> void:
	# Wave completed, prepare for next wave
	wave_in_progress = false
	
	# Ensure we've got valid data
	if not waves.has(current_zone) or current_wave_index >= waves[current_zone].size():
		push_warning("WaveManager: Cannot complete wave - invalid zone or wave index")
		# Reset to a valid state
		current_wave_index = 0
		next_action = "start_wave"
		wave_timer.wait_time = 2.0
		wave_timer.start()
		return
	
	# Get completion delay before incrementing wave index
	var completion_delay = waves[current_zone][current_wave_index].completion_delay
	
	# Increment wave index
	current_wave_index += 1
	
	# Emit completion signal
	emit_signal("wave_completed")
	
	# Start next wave after completion delay
	next_action = "start_wave"
	wave_timer.stop() # Ensure timer is stopped before starting again
	wave_timer.wait_time = completion_delay
	wave_timer.start()

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
	var viewport_rect = get_viewport().get_visible_rect()
	
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
