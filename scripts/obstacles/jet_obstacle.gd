# jet_obstacle.gd
extends Obstacle
class_name JetObstacle

@export var thruster_particle_color: Color = Color(0.7, 0.7, 1.0)
@export var thruster_size: float = 0.8
@onready var thruster_particles: CPUParticles2D = $ThrusterParticles if has_node("ThrusterParticles") else null

func _ready() -> void:
	super._ready()
	# Jets are fast with moderate damage
	damage = 20.0
	base_speed = 150.0
	movement_pattern = "sine"
	pattern_amplitude = 80.0
	pattern_frequency = 0.8
	
	# Setup thruster particles if they exist
	if thruster_particles:
		thruster_particles.emitting = true
		# Set custom color
		if thruster_particles.has_method("set_color"):
			thruster_particles.set_color(thruster_particle_color)

# Override initialize to set up jet-specific behavior
func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	
	# Jets should face downward and move in their facing direction
	rotation_degrees = 180.0
	
	# Start thruster particles
	if thruster_particles:
		thruster_particles.emitting = true

# Override handle_player_collision for jet-specific effects
func handle_player_collision() -> void:
	super.handle_player_collision()
	
	# Could add explosion effect specific to jets here
	if thruster_particles:
		thruster_particles.emitting = false
