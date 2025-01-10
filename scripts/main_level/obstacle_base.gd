# obstacle_base.gd
extends GameObject
class_name Obstacle

@export var damage: float = 10.0
@export var movement_pattern: String = "linear"  # linear, zigzag, sine
@export var pattern_amplitude: float = 50.0
@export var pattern_frequency: float = 1.0

var initial_x: float
var time_alive: float = 0.0

func _ready() -> void:
	super._ready()
	points = -10  # Negative points for hitting obstacles

func _process(delta: float) -> void:
	if is_active:
		time_alive += delta
		apply_movement_pattern(delta)

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	initial_x = spawn_position.x
	time_alive = 0.0

func apply_movement_pattern(delta: float) -> void:
	match movement_pattern:
		"linear":
			# Just fall straight down (handled by spawn manager)
			pass
		"zigzag":
			position.x = initial_x + cos(time_alive * pattern_frequency) * pattern_amplitude
		"sine":
			position.x = initial_x + sin(time_alive * pattern_frequency) * pattern_amplitude

# Override handle_player_collision for specific obstacle effects
func handle_player_collision() -> void:
	# Could add explosion effect, screen shake, etc. here
	super.handle_player_collision()
