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

	# Load the projectile scene if it's not already set
	if not projectile_scene:
		projectile_scene = load("res://scenes/effects/enemy_projectile_1.tscn")
		
	# Setup thruster particles if they exist
	if thruster_particles:
		thruster_particles.emitting = true
		# Set custom color
		if thruster_particles.has_method("set_color"):
			thruster_particles.set_color(thruster_particle_color)

	#print("JetObstacle after setup: can_shoot=" + str(can_shoot) + 
	#	  ", cooldown=" + str(shoot_cooldown) + 
	#	  ", chance=" + str(shoot_chance))
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

# Jets fire from 1-2 randomly chosen, distinct gun points
func _select_gun_points() -> Array:
	# Decide how many gun points to use (1-2 randomly)
	var num_guns = rng.randi_range(1, min(2, gun_points.size()))

	# Randomly select which gun points to use
	var selected_guns = []
	var available_guns = gun_points.duplicate()
	for i in range(num_guns):
		if available_guns.is_empty():
			break

		var index = rng.randi() % available_guns.size()
		selected_guns.append(available_guns[index])
		available_guns.remove_at(index)

	return selected_guns
