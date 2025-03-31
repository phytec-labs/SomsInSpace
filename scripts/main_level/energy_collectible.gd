# energy_collectible.gd
extends GameObject
class_name EnergyCollectible

@export var energy_value: float = 10.0
@export var rotation_speed: float = 10.0
@export var scale_variation: float = 0.3
@export var fall_speed: float = 100.0  # Speed at which collectible falls

var base_scale: float
var time_alive: float = 0.0

func _ready() -> void:
	super._ready()
	base_scale = scale.x
	print("Energy collectible initialized with points: ", points)

func _process(delta: float) -> void:
	if is_active:
		# Move downwards
		position.y += fall_speed * delta
		
		# Animate the width for 3D effect
		time_alive += delta
		var scale_factor = abs(cos(time_alive * rotation_speed))
		scale.x = base_scale * scale_factor
		
		# Check if off-screen
		check_if_offscreen()

# Override initialize to add some debugging
func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	print("Energy collectible spawned at position: ", spawn_position)

# Optional: Override handle_player_collision for specific effects
func handle_player_collision() -> void:
	# Could add particle effects, sound, etc. here
	print("Energy collectible collected! Points: ", points)
	super.handle_player_collision()
