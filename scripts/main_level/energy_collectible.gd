# energy_collectible.gd
extends GameObject
class_name EnergyCollectible

@export var energy_value: float = 10.0
@export var rotation_speed: float = 2.0

func _ready() -> void:
	super._ready()
	points = 10  # Positive points for collecting

func _process(delta: float) -> void:
	if is_active:
		# Rotate the energy collectible
		rotate(rotation_speed * delta)

# Optional: Override handle_player_collision for specific effects
func handle_player_collision() -> void:
	# Could add particle effects, sound, etc. here
	super.handle_player_collision()
