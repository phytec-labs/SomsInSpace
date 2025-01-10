# atmosphere_manager.gd
extends Node2D

# Node references
@onready var background: ColorRect = $Background
@onready var stars_particles: GPUParticles2D = $StarsParticles
@onready var clouds_particles: GPUParticles2D = $CloudsParticles

# Zone colors
const ZONE_COLORS = {
	"ground": Color(0.53, 0.81, 0.92, 1.0),      # Light blue sky
	"atmosphere": Color(0.28, 0.46, 0.8, 1.0),   # Darker blue
	"upper_atmosphere": Color(0.13, 0.19, 0.45, 1.0), # Deep blue
	"space": Color(0.05, 0.05, 0.1, 1.0)         # Almost black
}

# Transition settings
var current_color: Color
var target_color: Color
var transition_time: float = 0.0
const TRANSITION_DURATION: float = 3.0

# Stars visibility (0 to 1)
var star_visibility: float = 0.0
var target_star_visibility: float = 0.0

func _ready() -> void:
	# Set initial state
	current_color = ZONE_COLORS["ground"]
	target_color = current_color
	background.color = current_color
	
	# Set initial size
	update_background_size()
	
	# Initialize particles
	update_particle_systems(0.0)
	
	# Connect to window resize
	get_tree().root.size_changed.connect(update_background_size)

func update_background_size() -> void:
	var viewport_size = get_viewport_rect().size
	background.size = viewport_size
	background.position = Vector2.ZERO

func _process(delta: float) -> void:
	if transition_time < TRANSITION_DURATION:
		transition_time += delta
		var t = transition_time / TRANSITION_DURATION
		
		# Smooth transition using smoothstep
		t = smoothstep(0.0, 1.0, t)
		
		# Update background color
		background.color = current_color.lerp(target_color, t)
		
		# Update particle systems
		update_particle_systems(t)

func smoothstep(edge0: float, edge1: float, x: float) -> float:
	# Custom smoothstep implementation
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func set_zone(zone_name: String) -> void:
	if not ZONE_COLORS.has(zone_name):
		return
		
	current_color = background.color
	target_color = ZONE_COLORS[zone_name]
	transition_time = 0.0
	
	# Set star visibility targets based on zone
	match zone_name:
		"ground":
			target_star_visibility = 0.0
			clouds_particles.emitting = true
		"atmosphere":
			target_star_visibility = 0.3
			clouds_particles.emitting = true
		"upper_atmosphere":
			target_star_visibility = 0.7
			clouds_particles.emitting = false
		"space":
			target_star_visibility = 1.0
			clouds_particles.emitting = false

func update_particle_systems(transition_factor: float) -> void:
	# Update star visibility
	star_visibility = lerp(star_visibility, target_star_visibility, transition_factor)
	
	# Update particle systems
	if stars_particles:
		var process_material = stars_particles.process_material as ParticleProcessMaterial
		if process_material:
			process_material.initial_velocity_min = lerp(10.0, 50.0, star_visibility)
			process_material.initial_velocity_max = lerp(20.0, 100.0, star_visibility)
			stars_particles.amount = int(lerp(20.0, 100.0, star_visibility))
			
	# Adjust cloud particles based on height
	if clouds_particles:
		var cloud_process_material = clouds_particles.process_material as ParticleProcessMaterial
		if cloud_process_material:
			cloud_process_material.initial_velocity_min = lerp(50.0, 200.0, transition_factor)
			cloud_process_material.initial_velocity_max = lerp(100.0, 400.0, transition_factor)
