# obstacle.gd
extends GameObject
class_name Obstacle

# Base obstacle properties
@export var damage: float = 10.0
@export var base_speed: float = 100.0

# Movement pattern variables
var movement_pattern: String = "linear"  # linear, sine, zigzag
var pattern_amplitude: float = 50.0   # How far it moves side to side
var pattern_frequency: float = 1.0    # How fast it moves side to side
var pattern_time: float = 0.0        # Time tracker for movement patterns

# Formation variables
var is_formation_member: bool = false  # Is part of a formation?
var formation_id: int = -1            # Unique ID for the formation
var formation_offset: Vector2 = Vector2.ZERO  # Offset from formation center
var formation_local_position: Vector2 = Vector2.ZERO  # Local position in formation

# Optional rotation
@export var rotation_speed: float = 0.0  # Degrees per second

# Initial position tracking for patterns
var initial_x: float = 0.0

func _ready() -> void:
	super._ready()
	
	# Default points value for obstacles is negative (damages player)
	points = -10

func _process(delta: float) -> void:
	if not is_active:
		return
		
	pattern_time += delta
	
	# Calculate movement based on pattern
	var velocity = Vector2.ZERO
	
	# Base vertical movement (always move down)
	velocity.y = base_speed * speed_multiplier
	
	if is_formation_member:
		# Formation members move as part of the formation
		# The formation center moves down at a constant speed
		position.y += velocity.y * delta
		
		# Maintain formation relative positions
		# No additional pattern movement for formation members
	else:
		# Add horizontal movement based on pattern for non-formation members
		match movement_pattern:
			"linear":
				# Just move straight down
				pass
				
			"sine":
				# Sinusoidal side to side movement
				var sin_offset = sin(pattern_time * pattern_frequency) * pattern_amplitude
				velocity.x = cos(pattern_time * pattern_frequency) * pattern_amplitude * pattern_frequency
				position.x = initial_x + sin_offset
				
			"zigzag":
				# Sharp zigzag movement
				var zigzag = sign(sin(pattern_time * pattern_frequency * PI))
				velocity.x = zigzag * pattern_amplitude * pattern_frequency
	
		# Apply vertical movement for non-formation members
		position.y += velocity.y * delta
		
		# Apply horizontal movement if we're not using position-based patterns
		if movement_pattern == "linear" or movement_pattern == "zigzag":
			position.x += velocity.x * delta
	
	# Apply rotation if set
	if rotation_speed != 0:
		rotation_degrees += rotation_speed * delta
	
	# Check if off-screen
	check_if_offscreen()

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	initial_x = spawn_position.x
	pattern_time = 0.0
	
	# Reset formation variables
	if not is_formation_member:
		formation_id = -1
		formation_offset = Vector2.ZERO

func set_movement_pattern(pattern: String) -> void:
	movement_pattern = pattern

func set_speed_multiplier(multiplier: float) -> void:
	speed_multiplier = multiplier

func set_formation_member(is_member: bool) -> void:
	is_formation_member = is_member

# Set this obstacle as part of a formation
func set_formation_data(form_id: int, form_offset: Vector2) -> void:
	formation_id = form_id
	formation_offset = form_offset
	is_formation_member = true
	# Store local offset for patterns that might later be applied to the formation as a whole
	formation_local_position = formation_offset

func check_if_offscreen() -> void:
	var viewport_rect = get_viewport_rect()
	var margin = 100.0  # Margin beyond screen edges
	
	if (position.y > viewport_rect.size.y + margin or 
		position.y < -margin * 2 or
		position.x > viewport_rect.size.x + margin or
		position.x < -margin):
		emit_signal("screen_exited")
