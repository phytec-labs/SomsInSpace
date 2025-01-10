extends Node2D

class Nebula:
	var position: Vector2
	var size: Vector2
	var color: Color
	var speed: Vector2
	var points: PackedVector2Array
	var colors: PackedColorArray

	func _init(pos: Vector2, sz: Vector2, col: Color, spd: Vector2):
		position = pos
		size = sz
		color = col
		speed = spd
		generate_points(64)  # Increased number of points for more coverage

	func generate_points(point_count: int):
		points = PackedVector2Array()
		colors = PackedColorArray()
		var rng = RandomNumberGenerator.new()

		for i in range(point_count):
			# Create points in a grid-like pattern with some randomness
			var grid_size = 40.0  # Size of each pixel/block
			var grid_x = floor(rng.randf_range(-size.x/2, size.x/2) / grid_size) * grid_size
			var grid_y = floor(rng.randf_range(-size.y/2, size.y/2) / grid_size) * grid_size
			var point = Vector2(grid_x, grid_y)
			points.append(point)

			# Create color with random alpha
			var point_color = color
			point_color.a *= rng.randf_range(0.2, 0.8)
			colors.append(point_color)

var nebulas: Array[Nebula] = []
var rng = RandomNumberGenerator.new()

@export var nebula_count: int = 2
@export var nebula_colors: Array[Color] = [
	Color(0.4, 0.2, 0.6, 0.03),  # Purple
	Color(0.2, 0.4, 0.6, 0.03),  # Blue
	Color(0.6, 0.2, 0.4, 0.03)   # Red
]
@export var min_nebula_size: float = 400.0  # Increased size for better pixel coverage
@export var max_nebula_size: float = 800.0
@export var drift_speed: float = 10.0  # Slowed down movement

func _ready():
	generate_nebulas()

func generate_nebulas():
	nebulas.clear()
	var viewport_size = get_viewport_rect().size

	for i in range(nebula_count):
		var pos = Vector2(
			rng.randf_range(0, viewport_size.x),
			rng.randf_range(0, viewport_size.y)
		)
		var size = Vector2(
			rng.randf_range(min_nebula_size, max_nebula_size),
			rng.randf_range(min_nebula_size, max_nebula_size)
		)
		var color = nebula_colors[rng.randi() % nebula_colors.size()]
		var speed = Vector2(
			rng.randf_range(-drift_speed, drift_speed),
			rng.randf_range(-drift_speed, drift_speed)
		)

		nebulas.append(Nebula.new(pos, size, color, speed))

func _process(delta):
	var viewport_size = get_viewport_rect().size

	for nebula in nebulas:
		nebula.position += nebula.speed * delta

		# Wrap around screen
		if nebula.position.x < -nebula.size.x: nebula.position.x = viewport_size.x
		if nebula.position.x > viewport_size.x: nebula.position.x = -nebula.size.x
		if nebula.position.y < -nebula.size.y: nebula.position.y = viewport_size.y
		if nebula.position.y > viewport_size.y: nebula.position.y = -nebula.size.y

	queue_redraw()

func _draw():
	for nebula in nebulas:
		# Calculate time-based opacity variation
		var time_offset = Time.get_ticks_msec() * 0.001
		var alpha_mult = (sin(time_offset + nebula.position.x * 0.01) + 1.0) * 0.5

		# Draw each point in the nebula
		for i in range(nebula.points.size()):
			var pos = nebula.points[i] + nebula.position
			var color = nebula.colors[i]
			color.a *= alpha_mult * 0.5  # Reduce overall opacity and apply pulsing

			# Draw pixelated blocks instead of circles
			var block_size = 40.0  # Size of each pixel block
			var rect_pos = pos - Vector2(block_size/2, block_size/2)  # Center the block

			# Draw main block
			draw_rect(Rect2(rect_pos, Vector2(block_size, block_size)),
					 Color(color.r, color.g, color.b, color.a * 0.5))

			# Draw smaller internal block for variation
			var inner_pos = rect_pos + Vector2(block_size/4, block_size/4)
			var inner_size = block_size/2
			draw_rect(Rect2(inner_pos, Vector2(inner_size, inner_size)),
					 Color(color.r, color.g, color.b, color.a * 0.7))
