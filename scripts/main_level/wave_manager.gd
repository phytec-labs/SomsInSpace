# wave_manager.gd
extends Node

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

# Wave progression
var current_wave_index: int = 0
var current_group_index: int = 0
var enemies_spawned_in_group: int = 0
var wave_in_progress: bool = false
var current_zone: String = "ground"

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
	
	# Verify timers
	if not wave_timer:
		push_error("WaveManager: WaveTimer node not found!")
	else:
		wave_timer.timeout.connect(_on_wave_timer_timeout)
	
	if not enemy_timer:
		push_error("WaveManager: EnemyTimer node not found!")
	else:
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
	current_group_index = 0
	enemies_spawned_in_group = 0
	
	# Start first wave after a short delay
	wave_timer.start(1.0)

func stop_spawning() -> void:
	active = false
	wave_in_progress = false
	wave_timer.stop()
	enemy_timer.stop()

func set_zone(zone: String) -> void:
	# Update the zone and reset wave index
	if zone != current_zone:
		current_zone = zone
		current_wave_index = 0
		
		# If currently spawning, restart with new zone waves
		if active and not wave_in_progress:
			wave_timer.start(1.0)

# Wave control methods
func start_wave() -> void:
	if not active or wave_in_progress:
		return
	
	if not waves.has(current_zone) or waves[current_zone].size() == 0:
		push_warning("WaveManager: No waves defined for zone: " + current_zone)
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
	enemy_timer.wait_time = group.enemy_delay
	enemy_timer.start()

func spawn_enemy_in_group() -> void:
	if not wave_in_progress:
		return
	
	var wave_data = waves[current_zone][current_wave_index]
	var group = wave_data.groups[current_group_index]
	
	# Check if we've spawned all enemies in this group
	if enemies_spawned_in_group >= group.count:
		# Move to next group after delay
		current_group_index += 1
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
		formation_manager.create_formation(
			formation_type_enum,
			spawn_position,
			Callable(get_parent(), "spawn_obstacle")
		)
	
	enemies_spawned_in_group += 1
	
	# Continue spawning if more enemies in this group
	if enemies_spawned_in_group < group.count:
		enemy_timer.start()

func complete_wave() -> void:
	# Wave completed, prepare for next wave
	wave_in_progress = false
	current_wave_index += 1
	
	# Emit completion signal
	emit_signal("wave_completed")
	
	# Start next wave after completion delay
	var completion_delay = waves[current_zone][current_wave_index - 1].completion_delay
	wave_timer.wait_time = completion_delay
	wave_timer.start()

# Timer callbacks
func _on_wave_timer_timeout() -> void:
	if active and not wave_in_progress:
		start_wave()
	elif wave_in_progress:
		spawn_formation_group()

func _on_enemy_timer_timeout() -> void:
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

func _get_top_spawn_position() -> Vector2:
	var viewport_rect = get_viewport().get_visible_rect()
	var margin = 50
	var x_pos = randf_range(margin, viewport_rect.size.x - margin)
	var y_pos = -100  # Above screen
	return Vector2(x_pos, y_pos)

func _get_left_spawn_position() -> Vector2:
	var viewport_rect = get_viewport().get_visible_rect()
	var margin = 50
	var x_pos = -100  # Left of screen
	var y_pos = randf_range(margin, viewport_rect.size.y / 3)  # Upper third of screen
	return Vector2(x_pos, y_pos)

func _get_right_spawn_position() -> Vector2:
	var viewport_rect = get_viewport().get_visible_rect()
	var margin = 50
	var x_pos = viewport_rect.size.x + 100  # Right of screen
	var y_pos = randf_range(margin, viewport_rect.size.y / 3)  # Upper third of screen
	return Vector2(x_pos, y_pos)

func _get_bottom_spawn_position() -> Vector2:
	var viewport_rect = get_viewport().get_visible_rect()
	var margin = 50
	var x_pos = randf_range(margin, viewport_rect.size.x - margin)
	var y_pos = viewport_rect.size.y + 100  # Below screen
	return Vector2(x_pos, y_pos)
