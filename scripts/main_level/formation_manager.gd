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

var formation_patterns = ["linear", "sine", "zigzag", "spiral"]
var default_formation_speeds = {
	"linear": 1.0,
	"sine": 0.8,
	"zigzag": 0.9,
	"spiral": 0.7
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
var current_formation_id: int = 0  # Used to generate unique IDs for formations
var active_formations: Dictionary = {}  # Track active formations by ID
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

# Add a new method to update all formations
func _process(delta: float) -> void:
	# Update active formations with additional movement patterns
	for formation_id in active_formations.keys():
		var formation = active_formations[formation_id]

		# Check if formation is still active (has objects)
		if formation.objects.is_empty():
			active_formations.erase(formation_id)
			continue

		# Remove any objects that are no longer in the scene
		for i in range(formation.objects.size() - 1, -1, -1):
			if not is_instance_valid(formation.objects[i]) or not formation.objects[i].is_active:
				formation.objects.remove_at(i)

		# If no objects left, remove the formation
		if formation.objects.is_empty():
			active_formations.erase(formation_id)
			continue

		# Update formation pattern time
		formation.pattern_time += delta

		# Calculate pattern offsets based on formation's pattern
		var pattern_offset = Vector2.ZERO
		var viewport_center_x = _get_viewport_rect().size.x / 2.0

		# Add center-pulling for side-spawned formations
		if formation.is_side_spawn:
			var direction_to_center = sign(viewport_center_x - formation.base_position.x)
			formation.base_position.x += formation.speed * delta * formation.center_pull_strength * direction_to_center

		# Calculate vertical movement (always moves down)
		formation.base_position.y += formation.speed * delta

		# Calculate horizontal movement based on pattern
		match formation.pattern:
			"linear":
				# Just move downward, no horizontal pattern
				pass

			"sine":
				# Sinusoidal side to side movement
				pattern_offset.x = sin(formation.pattern_time * formation.frequency) * formation.amplitude

			"zigzag":
				# Sharp zigzag movement
				pattern_offset.x = sign(sin(formation.pattern_time * formation.frequency * PI)) * formation.amplitude

			"spiral":
				# Spiral movement
				formation.rotation += delta * formation.frequency
				pattern_offset.x = cos(formation.rotation) * formation.amplitude
				pattern_offset.y = sin(formation.rotation) * formation.amplitude * 0.5

		# Update all objects in this formation with the new positions
		for obj in formation.objects:
			if is_instance_valid(obj) and obj.is_active:
				obj.global_position = formation.base_position + obj.formation_offset + pattern_offset

# Creates a specific formation type at the given position
func create_formation(formation_type: FormationType, base_position: Vector2, spawn_func: Callable) -> Array:
	var formation_def = formation_definitions[formation_type]
	var zone_settings = zone_formation_settings[current_zone]

	# Generate a unique formation ID
	current_formation_id += 1
	var formation_id = current_formation_id

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
			# Set formation data if the object supports it
			if object.has_method("set_formation_data"):
				object.set_formation_data(formation_id, offset)
			formation_objects.append(object)

	# Store information about this formation
	if not formation_objects.is_empty():
		# Select a pattern for the formation
		var pattern = formation_patterns[rng.randi() % formation_patterns.size()]
		var speed_multiplier = default_formation_speeds[pattern]

		# Assign appropriate pattern attributes based on pattern type
		var amplitude = 70.0
		var frequency = 0.5
		if pattern == "zigzag":
			frequency = 0.3
		elif pattern == "spiral":
			frequency = 0.2

		# Different patterns for different zones
		if current_zone == "upper_atmosphere" or current_zone == "space":
			amplitude *= 1.5
			frequency *= 1.2

		active_formations[formation_id] = {
			"type": formation_type,
			"base_position": base_position,
			"objects": formation_objects,
			"speed": formation_objects[0].base_speed * formation_objects[0].speed_multiplier * speed_multiplier,
			"pattern": pattern,  # Formation movement pattern
			"pattern_time": 0.0,
			"amplitude": amplitude,
			"frequency": frequency,
			"rotation": 0.0,  # For spiral patterns
			"is_side_spawn": _is_side_spawn(base_position),
			"center_pull_strength": 0.5 if _is_side_spawn(base_position) else 0.0
		}

		# Set all objects to use the formation's movement rather than their own
		for obj in formation_objects:
			if obj.has_method("set_use_formation_movement"):
				obj.set_use_formation_movement(true)

		# Emit signal with created formation
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

	# If viewport_size was passed as zero, get it from the viewport
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		viewport_size = _get_viewport_rect().size

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
				# Ensure enemies spawn near or above the top of the screen
				y_pos = rng.randf_range(-50.0, 150.0)
			2: # Bottom (only in space zone)
				if current_zone == "space":
					x_pos = rng.randf_range(max_spread, viewport_size.x - max_spread)
					y_pos = viewport_size.y + 100.0
			3: # Left
				x_pos = -100.0
				# Ensure enemies spawn near or above the top of the screen
				y_pos = rng.randf_range(-50.0, 150.0)

	return Vector2(x_pos, y_pos)

func _is_side_spawn(position: Vector2) -> bool:
	var viewport_rect = _get_viewport_rect()
	var screen_edge_margin = 50.0
	return (position.x < -screen_edge_margin or position.x > viewport_rect.size.x + screen_edge_margin)

func _get_viewport_rect() -> Rect2:
	# Get the viewport from the scene tree
	var viewport = get_viewport()
	if viewport:
		return viewport.get_visible_rect()
	# Fallback with default size if viewport isn't available
	return Rect2(0, 0, 720, 1280)
