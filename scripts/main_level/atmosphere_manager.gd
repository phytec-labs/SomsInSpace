# atmosphere_manager.gd
extends Node2D

# Node references
@onready var background: ColorRect = $Background
@onready var starfield: Node2D = $Starfield

# Zone colors
@export_group("Zone Colors")
@export var ground_color: Color = Color(0.53, 0.81, 0.92, 1.0)      # Light blue sky
@export var atmosphere_color: Color = Color(0.28, 0.46, 0.8, 1.0)   # Darker blue
@export var upper_atmosphere_color: Color = Color(0.13, 0.19, 0.45, 1.0) # Deep blue
@export var space_color: Color = Color(0.05, 0.05, 0.1, 1.0)         # Almost black

# Star visibility settings
@export_group("Star Visibility")
@export_range(0.0, 1.0) var ground_star_visibility: float = 0.0
@export_range(0.0, 1.0) var atmosphere_star_visibility: float = 0.3
@export_range(0.0, 1.0) var upper_atmosphere_star_visibility: float = 0.7
@export_range(0.0, 1.0) var space_star_visibility: float = 1.0

# Transition settings
@export_group("Transition Settings")
@export var transition_duration: float = 2.5
@export var gradient_size: float = 0.1

var transition_time: float = 0.0
var transition_active: bool = false

# Current zone tracking
var current_zone: String = "ground"

func _ready() -> void:
	# Ensure the background covers the viewport
	background.size = get_viewport_rect().size
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

	# Set initial shader parameters
	var shader_material = background.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("current_color", get_zone_color("ground"))
		shader_material.set_shader_parameter("target_color", get_zone_color("ground"))
		shader_material.set_shader_parameter("transition_progress", 1.0)
		shader_material.set_shader_parameter("gradient_size", gradient_size)

func _process(delta: float) -> void:
	if transition_active:
		transition_time += delta
		var progress = clamp(transition_time / transition_duration, 0.0, 1.0)

		var shader_material = background.material as ShaderMaterial
		if shader_material:
			shader_material.set_shader_parameter("transition_progress", progress)

		if progress >= 1.0:
			transition_active = false

func _on_viewport_size_changed():
	background.size = get_viewport_rect().size

func get_zone_color(zone_name: String) -> Color:
	match zone_name:
		"ground":
			return ground_color
		"atmosphere":
			return atmosphere_color
		"upper_atmosphere":
			return upper_atmosphere_color
		"space":
			return space_color
		_:
			return ground_color

func get_zone_star_visibility(zone_name: String) -> float:
	match zone_name:
		"ground":
			return ground_star_visibility
		"atmosphere":
			return atmosphere_star_visibility
		"upper_atmosphere":
			return upper_atmosphere_star_visibility
		"space":
			return space_star_visibility
		_:
			return 0.0

func set_zone(zone_name: String) -> void:
	# Verify zone exists
	if not get_zone_color(zone_name) or zone_name == current_zone:
		return

	var shader_material = background.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("current_color", get_zone_color(current_zone))
		shader_material.set_shader_parameter("target_color", get_zone_color(zone_name))
		shader_material.set_shader_parameter("transition_progress", 0.0)

	current_zone = zone_name
	transition_time = 0.0
	transition_active = true

	# Update star visibility
	if starfield and starfield.has_method("set_star_visibility"):
		starfield.set_star_visibility(get_zone_star_visibility(zone_name), transition_duration)
