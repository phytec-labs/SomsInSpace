extends Node2D

class Star:
	var position: Vector2
	var size: float
	var flicker_speed: float
	var time_offset: float
	var base_alpha: float
	
	func _init(pos: Vector2, sz: float, speed: float, offset: float, alpha: float):
		position = pos
		size = sz
		flicker_speed = speed
		time_offset = offset
		base_alpha = alpha

var stars: Array[Star] = []
var rng = RandomNumberGenerator.new()

@export var star_count: int = 100
@export var min_star_size: float = 1.0
@export var max_star_size: float = 3.0
@export var min_flicker_speed: float = 1.0
@export var max_flicker_speed: float = 3.0

func _ready():
	generate_stars()

func generate_stars():
	stars.clear()
	var viewport_size = get_viewport_rect().size
	
	for i in range(star_count):
		var pos = Vector2(
			rng.randf_range(0, viewport_size.x),
			rng.randf_range(0, viewport_size.y)
		)
		var size = rng.randf_range(min_star_size, max_star_size)
		var speed = rng.randf_range(min_flicker_speed, max_flicker_speed)
		var offset = rng.randf_range(0, PI * 2)  # Random starting phase
		var base_alpha = rng.randf_range(0.5, 1.0)  # Random base brightness
		
		stars.append(Star.new(pos, size, speed, offset, base_alpha))

func _draw():
	for star in stars:
		var flicker = (sin(Time.get_ticks_msec() * 0.001 * star.flicker_speed + star.time_offset) + 1) * 0.5
		var alpha = star.base_alpha * (0.5 + 0.5 * flicker)  # Flicker between 50% and 100% of base alpha
		draw_circle(star.position, star.size, Color(1, 1, 1, alpha))

func _process(_delta):
	queue_redraw()  # Request redraw every frame to update star animations
