extends Node2D
class_name BackgroundCloud

@export var horizontal_speed: float = 15.0      # Slower horizontal movement
@export var vertical_speed: float = 25.0        # Slower vertical movement
@export var size_variation: float = 0.3         # Random size variation (±30%)
@export var base_opacity: float = 0.6           # Base opacity for clouds
@export var opacity_variation: float = 0.2      # Random opacity variation

var is_active: bool = false
var horizontal_direction: float
var base_scale: Vector2
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	# Set lower z-index to appear behind obstacles
	z_index = -10
	
	# Random size variation
	var scale_factor = 1.0 + randf_range(-size_variation, size_variation)
	base_scale = Vector2(scale_factor, scale_factor)
	scale = base_scale
	
	# Randomly choose direction (-1 for left, 1 for right)
	horizontal_direction = 1.0 if randf() > 0.5 else -1.0
	
	deactivate()

func initialize(spawn_position: Vector2) -> void:
	position = spawn_position
	is_active = true
	
	# Set random opacity
	modulate.a = base_opacity + randf_range(-opacity_variation, opacity_variation)
	scale = base_scale
	show()

func deactivate() -> void:
	is_active = false
	hide()

func _process(delta: float) -> void:
	if not is_active:
		return
		
	# Apply slow horizontal and vertical movement
	position.x += horizontal_speed * horizontal_direction * delta
	position.y += vertical_speed * delta
	
	# Check if cloud has moved off screen
	var viewport_size = get_viewport_rect().size
	if position.y > viewport_size.y + 100:
		deactivate()
