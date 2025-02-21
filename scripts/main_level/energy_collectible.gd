# energy_collectible.gd
extends GameObject
class_name EnergyCollectible

@export var energy_value: float = 10.0
@export var rotation_speed: float = 10.0
@export var scale_variation: float = 0.3

var base_scale: float
var time_alive: float = 0.0

func _ready() -> void:
	super._ready()
	points = 10
	base_scale = scale.x

func _process(delta: float) -> void:
	if is_active:
		time_alive += delta
		# Simulate 3D rotation by scaling width
		# Absolute value of cosine gives a full 0-1-0 scale effect
		var scale_factor = abs(cos(time_alive * rotation_speed))
		scale.x = base_scale * scale_factor

# Optional: Override handle_player_collision for specific effects
func handle_player_collision() -> void:
	# Could add particle effects, sound, etc. here
	super.handle_player_collision()
