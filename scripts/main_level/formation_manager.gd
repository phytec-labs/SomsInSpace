# formation_manager.gd
extends Node

signal formation_created(formation_objects)

# Formation types
enum FormationType {
	LINE,         # Simple horizontal line
	V_SHAPE,      # V formation
	SQUARE,       # Square/rectangle group
	DIAGONAL,     # Diagonal line
	WAVE,         # Wave/sine pattern
	CIRCLE,       # Circle/arc formation
	RANDOM,       # Random cluster within bounds
}

# Formation definitions - store standard parameters for each formation
var formation_definitions = {
	FormationType.LINE: {
		"object_count": 5,
	},
	FormationType.V_SHAPE: {
		"object_count": 5,
	},
	FormationType.SQUARE: {
		"object_count": 9,
	},
	FormationType.DIAGONAL: {
		"object_count": 7,
	},
	FormationType.WAVE: {
		"object_count": 8,
	},
	FormationType.CIRCLE: {
		"object_count": 8,
	},
	FormationType.RANDOM: {
		"object_count": 6,
	}
}

# Zone-specific formation settings
var zone_formation_settings = {
	"ground": {
		"allowed_formations": [FormationType.LINE, FormationType.V_SHAPE, FormationType.DIAGONAL],
		"min_spread": 60.0,
		"max_spread": 120.0,
		"min_objects": 3,
		"max_objects": 5
	},
	"atmosphere": {
		"allowed_formations": [FormationType.LINE, FormationType.V_SHAPE, FormationType.SQUARE, FormationType.WAVE],
		"min_spread": 70.0,
		"max_spread": 150.0,
		"min_objects": 4,
		"max_objects": 7
	},
	"upper_atmosphere": {
		"allowed_formations": [FormationType.V_SHAPE, FormationType.SQUARE, FormationType.CIRCLE, FormationType.WAVE],
		"min_spread": 80.0,
		"max_spread": 180.0,
		"min_objects": 5,
		"max_objects": 9
	},
	"space": {
		"allowed_formations": [FormationType.SQUARE, FormationType.CIRCLE, FormationType.DIAGONAL, FormationType.RANDOM],
		"min_spread": 100.0,
		"max_spread": 200.0,
		"min_objects": 6,
		"max_objects": 12
	}
}

var current_zone = "ground"
var rng = RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

# Sets the current zone to adjust formation settings
func set_zone(zone: String) -> void:
	if zone_formation_settings.has(zone):
		current_zone = zone

# Creates a random formation type valid for the current zone
func create_random_formation(base_position: Vector2, spawn_func: Callable) -> Array:
	var zone_settings = zone_formation_settings[current_zone]

	# Select random formation type from allowed types
	var formation_types = zone_settings.allowed_formations
	var formation_type = formation_types[rng.randi() % formation_types.size()]

	return create_formation(formation_type, base_position, spawn_func)

# Creates a specific formation type at the given position
func create_formation(formation_type: FormationType, base_position: Vector2, spawn_func: Callable) -> Array:
	var formation_def = formation_definitions[formation_type]
	var zone_settings = zone_formation_settings[current_zone]

	# Determine number of objects in this formation instance
	var object_count = rng.randi_range(
		min(formation_def.object_count, zone_settings.min_objects),
		min(formation_def.object_count, zone_settings.max_objects)
	)

	# Determine spread for this formation
	var spread = rng.randf_range(zone_settings.min_spread, zone_settings.max_spread)

	# Create the formation objects
	var formation_objects = []

	for i in range(object_count):
		# Get position offset for this object in the formation
		var offset = get_formation_position(formation_type, i, object_count, spread)
		var spawn_position = base_position + offset

		# Spawn the actual object
		var object = spawn_func.call(spawn_position)
		if object:
			formation_objects.append(object)

	# Emit signal with created formation
	if not formation_objects.is_empty():
		emit_signal("formation_created", formation_objects)

	return formation_objects

# Calculate the position for a specific formation type
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
			var side_length = int(ceil(sqrt(count)))  # Convert to int explicitly
			var x_index = index % side_length
			var y_index = int(index / side_length)  # Also convert this to int for consistency
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
			var x_pos = (progress * 2 - 1) * spread
			var y_pos = sin(progress * PI * 2) * spread * 0.3
			return Vector2(x_pos, y_pos)

		FormationType.CIRCLE:
			var angle = (index / float(count)) * PI * 2
			var x_pos = cos(angle) * spread
			var y_pos = sin(angle) * spread
			return Vector2(x_pos, y_pos)

		FormationType.RANDOM:
			var temp_rng = RandomNumberGenerator.new()
			temp_rng.seed = index * 1000  # Deterministic randomness
			var x_pos = (temp_rng.randf() * 2 - 1) * spread
			var y_pos = (temp_rng.randf() * 2 - 1) * spread * 0.5
			return Vector2(x_pos, y_pos)

		_:
			# Default to LINE if unknown type
			var x_pos = (index - (count - 1) / 2.0) * spread
			return Vector2(x_pos, 0)

# Generate a spawn position based on viewport and zone
func generate_spawn_position(viewport_size: Vector2) -> Vector2:
	var zone_settings = zone_formation_settings[current_zone]
	var max_spread = zone_settings.max_spread

	# Default to spawning at top
	var x_pos = rng.randf_range(max_spread, viewport_size.x - max_spread)
	var y_pos = -100.0 # Just above the screen

	# In higher zones, enemies can come from sides or bottom too
	if current_zone == "upper_atmosphere" or current_zone == "space":
		var spawn_side = rng.randi() % 4 # 0=top, 1=right, 2=bottom, 3=left

		match spawn_side:
			0: # Top
				x_pos = rng.randf_range(max_spread, viewport_size.x - max_spread)
				y_pos = -100.0
			1: # Right
				x_pos = viewport_size.x + 100.0
				y_pos = rng.randf_range(max_spread, viewport_size.y / 2)
			2: # Bottom (only in space zone)
				if current_zone == "space":
					x_pos = rng.randf_range(max_spread, viewport_size.x - max_spread)
					y_pos = viewport_size.y + 100.0
			3: # Left
				x_pos = -100.0
				y_pos = rng.randf_range(max_spread, viewport_size.y / 2)

	return Vector2(x_pos, y_pos)
