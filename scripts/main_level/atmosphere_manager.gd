# atmosphere_manager.gd
extends Node2D

# Node references
@onready var background: ColorRect = $Background
@onready var starfield: Node2D = $Starfield

# Per-zone background colors and star visibility come from the ZoneDefinition
# resources (data/zones/*.tres); main_level.gd passes them to
# set_zone_appearance() whenever the zone changes.

# Shown until the first set_zone_appearance() call
@export var initial_color: Color = Color(0.05, 0.05, 0.1, 1.0)

# Transition settings
@export_group("Transition Settings")
@export var transition_duration: float = 2.5
@export var gradient_size: float = 0.1

var transition_time: float = 0.0
var transition_active: bool = false

# Current zone tracking ("" until the first set_zone_appearance())
var current_zone: String = ""
var current_color: Color

func _ready() -> void:
	# Ensure the background covers the viewport
	background.size = get_viewport_rect().size
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

	# Set initial shader parameters
	current_color = initial_color
	var shader_material = background.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("current_color", initial_color)
		shader_material.set_shader_parameter("target_color", initial_color)
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

# Switch to a zone's appearance: wipe the background to `color` (shader
# transition) and fade the starfield to `star_visibility`. The first call
# (level start) applies instantly instead of transitioning.
func set_zone_appearance(zone_id: String, color: Color, star_visibility: float) -> void:
	if zone_id == current_zone:
		return
	var is_initial := current_zone.is_empty()

	var shader_material = background.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("current_color", color if is_initial else current_color)
		shader_material.set_shader_parameter("target_color", color)
		shader_material.set_shader_parameter("transition_progress", 1.0 if is_initial else 0.0)

	current_zone = zone_id
	current_color = color
	transition_time = 0.0
	transition_active = not is_initial

	# Update star visibility
	if starfield and starfield.has_method("set_star_visibility"):
		starfield.set_star_visibility(star_visibility, 0.001 if is_initial else transition_duration)
