# atmosphere_manager.gd
extends Node2D

# Node references
@onready var background: ColorRect = $Background

# Zone colors
const ZONE_COLORS = {
	"ground": Color(0.53, 0.81, 0.92, 1.0),      # Light blue sky
	"atmosphere": Color(0.28, 0.46, 0.8, 1.0),   # Darker blue
	"upper_atmosphere": Color(0.13, 0.19, 0.45, 1.0), # Deep blue
	"space": Color(0.05, 0.05, 0.1, 1.0)         # Almost black
}

# Transition settings
var transition_time: float = 0.0
const TRANSITION_DURATION: float = 2.5
var transition_active: bool = false

# Stars visibility (0 to 1)
var star_visibility: float = 0.0
var target_star_visibility: float = 0.0

# Current zone tracking
var current_zone: String = "ground"

func _ready() -> void:
	# Ensure the background covers the viewport
	background.size = get_viewport_rect().size
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

	# Set initial shader parameters
	var shader_material = background.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("current_color", ZONE_COLORS["ground"])
		shader_material.set_shader_parameter("target_color", ZONE_COLORS["ground"])
		shader_material.set_shader_parameter("transition_progress", 1.0)
		shader_material.set_shader_parameter("gradient_size", 0.1)

func _process(delta: float) -> void:
	if transition_active:
		transition_time += delta
		var progress = clamp(transition_time / TRANSITION_DURATION, 0.0, 1.0)

		var shader_material = background.material as ShaderMaterial
		if shader_material:
			shader_material.set_shader_parameter("transition_progress", progress)

		if progress >= 1.0:
			transition_active = false

func _on_viewport_size_changed():
	background.size = get_viewport_rect().size

func set_zone(zone_name: String) -> void:
	if not ZONE_COLORS.has(zone_name) or zone_name == current_zone:
		return

	var shader_material = background.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("current_color", ZONE_COLORS[current_zone])
		shader_material.set_shader_parameter("target_color", ZONE_COLORS[zone_name])
		shader_material.set_shader_parameter("transition_progress", 0.0)

	current_zone = zone_name
	transition_time = 0.0
	transition_active = true

	# Set star visibility targets based on zone
	match zone_name:
		"ground":
			target_star_visibility = 0.0
		"atmosphere":
			target_star_visibility = 0.3
		"upper_atmosphere":
			target_star_visibility = 0.7
		"space":
			target_star_visibility = 1.0
