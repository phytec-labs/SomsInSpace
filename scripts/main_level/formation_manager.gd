# formation_manager.gd
class_name FormationManager
extends Node2D

const FormationSettingsScript := preload("res://scripts/data/formation_settings.gd")

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

# Current zone's formation tuning (FormationSettings, from the zone's
# ZoneDefinition; see set_zone())
var settings: FormationSettingsScript
var current_formation_id: int = 0  # Used to generate unique IDs for formations
var active_formations: Dictionary = {}  # Track active formations by ID
var rng = RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

# Sets the current zone (a ZoneDefinition) to adjust formation settings
func set_zone(zone: Resource) -> void:
	if zone and zone.formation_settings:
		settings = zone.formation_settings
	else:
		push_warning("FormationManager: zone has no FormationSettings; keeping previous settings")

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
			# A pooled obstacle may have been reused by a newer formation; it
			# then belongs to that formation only
			var member = formation.objects[i]
			if not is_instance_valid(member) or not member.is_active or member.formation_id != formation_id:
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
			var distance_to_center = viewport_center_x - formation.base_position.x
			var pull_threshold = 20.0
			
			# Only apply pulling force when outside threshold
			if abs(distance_to_center) > pull_threshold:
				# Use a fixed direction value (+1 or -1) instead of recalculating sign
				if not formation.has("center_pull_direction"):
					formation.center_pull_direction = 1.0 if distance_to_center > 0 else -1.0
				
				# Apply movement with fixed direction
				var pull_amount = formation.speed * delta * formation.center_pull_strength
				formation.base_position.x += pull_amount * formation.center_pull_direction
				
				# Check if we've crossed center and need to stop pulling
				var new_distance = viewport_center_x - formation.base_position.x
				if distance_to_center * new_distance <= 0:  # Sign changed = we crossed center
					formation.is_side_spawn = false  # Stop center pulling completely

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
				# Performance-optimized zigzag movement
				# We'll use a simpler linear interpolation approach
				
				# We store our current movement direction in the formation data
				if not formation.has("zigzag_direction"):
					formation.zigzag_direction = 1.0
					formation.zigzag_position = 0.0
					
				# Update position along the zigzag path
				formation.zigzag_position += formation.zigzag_direction * formation.frequency * delta
				
				# Check for direction change when we reach amplitude boundaries
				if formation.zigzag_position >= 1.0:
					formation.zigzag_position = 1.0
					formation.zigzag_direction = -1.0
				elif formation.zigzag_position <= -1.0:
					formation.zigzag_position = -1.0
					formation.zigzag_direction = 1.0
					
				# Map the position to actual offset
				pattern_offset.x = formation.zigzag_position * formation.amplitude

			"spiral":
				# Spiral movement
				formation.rotation += delta * formation.frequency
				pattern_offset.x = cos(formation.rotation) * formation.amplitude
				pattern_offset.y = sin(formation.rotation) * formation.amplitude * 0.5

		# Update all objects in this formation with the new positions
		for obj in formation.objects:
			if is_instance_valid(obj) and obj.is_active and obj.formation_id == formation_id:
				obj.global_position = formation.base_position + obj.formation_offset + pattern_offset

# Creates a specific formation type at the given position
func create_formation(formation_type: FormationType, base_position: Vector2, spawn_func: Callable) -> Array:
	var formation_def = formation_definitions[formation_type]
	if settings == null:
		push_warning("FormationManager: no FormationSettings set; call set_zone() first")
		return []

	# Generate a unique formation ID
	current_formation_id += 1
	var formation_id = current_formation_id

	# Determine number of objects in this formation instance
	var object_count = rng.randi_range(
		min(formation_def.object_count, settings.min_objects),
		min(formation_def.object_count, settings.max_objects)
	)

	# Determine spread for this formation
	var spread = rng.randf_range(settings.min_spread, settings.max_spread)

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

		# Zone-specific pattern scaling
		amplitude *= settings.pattern_amplitude_scale
		frequency *= settings.pattern_frequency_scale

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
			var x_pos = (progress * 2 - 1) * spread * 1.5
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
