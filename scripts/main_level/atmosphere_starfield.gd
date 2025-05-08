# Optimized version of atmosphere_starfield.gd
extends Node2D

class Star:
	var position: Vector2
	var size: float
	var flicker_speed: float
	var time_offset: float
	var base_alpha: float
	var color: Color
	var flicker_value: float = 0.0
	var update_counter: int = 0

	func _init(pos: Vector2, sz: float, speed: float, offset: float, alpha: float, col: Color):
		position = pos
		size = sz
		flicker_speed = speed
		time_offset = offset
		base_alpha = alpha
		color = col

class ShootingStar:
	var position: Vector2
	var velocity: Vector2
	var length: float
	var lifetime: float
	var max_lifetime: float

	func _init(pos: Vector2, vel: Vector2, tail_length: float, life: float):
		position = pos
		velocity = vel
		length = tail_length
		lifetime = life
		max_lifetime = life

var stars: Array[Star] = []
var shooting_stars: Array[ShootingStar] = []
var rng = RandomNumberGenerator.new()

@export var star_count: int = 50  # Reduced from 100
@export var min_star_size: float = 1.0
@export var max_star_size: float = 3.0
@export var min_flicker_speed: float = 1.0
@export var max_flicker_speed: float = 3.0
@export var star_colors: Array[Color] = [
	Color(1.0, 1.0, 1.0),    # White
	Color(0.9, 0.9, 1.0),    # Slight blue
	Color(1.0, 0.9, 0.9),    # Slight red
	Color(1.0, 1.0, 0.9),    # Slight yellow
]
@export var color_variation: float = 0.1
@export var shooting_star_chance: float = 0.01  # Reduced from 0.02
@export var shooting_star_speed: float = 500.0
@export var shooting_star_length: float = 30.0
@export var shooting_star_lifetime: float = 1.0

var current_alpha_multiplier: float = 0.0
var target_alpha_multiplier: float = 0.0
var transition_speed: float = 1.0

@export var scroll_speed: float = 50.0
@export var update_frequency: int = 2  # Update stars every N frames

# Optimization: Pre-calculate sin values 
var sin_table: Array = []
var sin_table_size: int = 100
var frame_counter: int = 0
var global_time: float = 0.0

# Optimization: Draw batching
var draw_positions: PackedVector2Array = PackedVector2Array()
var draw_colors: PackedColorArray = PackedColorArray()
var draw_sizes: PackedFloat32Array = PackedFloat32Array()

func _ready():
	# Initialize sin table for faster lookups
	_init_sin_table()
	generate_stars()
	# Initialize drawing arrays
	_init_draw_arrays()

func _init_sin_table():
	sin_table.resize(sin_table_size)
	for i in range(sin_table_size):
		var angle = (i / float(sin_table_size)) * TAU
		sin_table[i] = sin(angle)

func _init_draw_arrays():
	draw_positions.resize(star_count)
	draw_colors.resize(star_count)
	draw_sizes.resize(star_count)

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
		var offset = rng.randf_range(0, PI * 2)
		var base_alpha = rng.randf_range(0.5, 1.0)

		var base_color = star_colors[rng.randi() % star_colors.size()]
		var varied_color = Color(
			clampf(base_color.r + rng.randf_range(-color_variation, color_variation), 0, 1),
			clampf(base_color.g + rng.randf_range(-color_variation, color_variation), 0, 1),
			clampf(base_color.b + rng.randf_range(-color_variation, color_variation), 0, 1)
		)

		stars.append(Star.new(pos, size, speed, offset, base_alpha, varied_color))

func _process(delta):
	# Update global time
	global_time += delta
	frame_counter += 1
	
	# Update alpha transition
	current_alpha_multiplier = lerp(current_alpha_multiplier, target_alpha_multiplier, delta * transition_speed)

	# Optimization: Only update stars on certain frames
	if frame_counter % update_frequency == 0:
		# Update star positions
		var viewport_size = get_viewport_rect().size
		for i in range(stars.size()):
			var star = stars[i]
			
			# Update position
			star.position.y += scroll_speed * delta * update_frequency
			
			# Wrap stars to top when they go below screen
			if star.position.y > viewport_size.y:
				star.position.y = 0
				star.position.x = rng.randf_range(0, viewport_size.x)
			
			# Optimization: Update flicker value less frequently
			star.update_counter += 1
			if star.update_counter >= 3:  # Update flicker every 3 updates
				star.update_counter = 0
				
				# Use sin table for faster calculation
				var time_index = int((global_time * star.flicker_speed + star.time_offset) * sin_table_size / TAU) % sin_table_size
				var flicker = (sin_table[time_index] + 1) * 0.5
				star.flicker_value = flicker
			
			# Update draw arrays
			var flicker = star.flicker_value
			var alpha = star.base_alpha * (0.5 + 0.5 * flicker) * current_alpha_multiplier
			var draw_color = star.color
			draw_color.a = alpha
			
			draw_positions[i] = star.position
			draw_colors[i] = draw_color
			draw_sizes[i] = star.size

	# Optimization: Update shooting stars less frequently in lower visibility
	if target_alpha_multiplier > 0.8 and frame_counter % 2 == 0:
		update_shooting_stars(delta * 2)  # Compensate for less frequent updates

	queue_redraw()

func update_shooting_stars(delta: float) -> void:
	# Optimization: Simplified shooting star management
	# Update existing shooting stars
	for i in range(shooting_stars.size() - 1, -1, -1):
		var shooting_star = shooting_stars[i]
		shooting_star.position += shooting_star.velocity * delta
		shooting_star.lifetime -= delta

		if shooting_star.lifetime <= 0:
			shooting_stars.remove_at(i)

	# Spawn new shooting stars with reduced chance
	if randf() < shooting_star_chance * delta:
		spawn_shooting_star()

func spawn_shooting_star():
	var viewport_size = get_viewport_rect().size
	var start_pos = Vector2(
		rng.randf_range(-100, viewport_size.x + 100),
		-50
	)

	var angle = rng.randf_range(PI * 0.2, PI * 0.8)
	var velocity = Vector2(cos(angle), sin(angle)) * shooting_star_speed

	shooting_stars.append(ShootingStar.new(
		start_pos,
		velocity,
		shooting_star_length,
		shooting_star_lifetime
	))

func _draw():
	# Optimization: Batch drawing stars
	# We'll draw all stars with similar properties together to reduce draw calls
	for i in range(star_count):
		if i >= stars.size(): break
		
		# Skip stars with extremely low alpha
		if draw_colors[i].a < 0.01:
			continue
			
		draw_circle(draw_positions[i], draw_sizes[i], draw_colors[i])

	# Draw shooting stars (these are fewer, so less optimization needed)
	for shooting_star in shooting_stars:
		var fade = shooting_star.lifetime / shooting_star.max_lifetime * current_alpha_multiplier
		if fade < 0.01: continue
		
		var tail_start = shooting_star.position
		var tail_end = shooting_star.position - shooting_star.velocity.normalized() * shooting_star.length
		draw_line(tail_start, tail_end, Color(1, 1, 1, fade), 2.0)

func set_star_visibility(target: float, transition_time: float = 1.0) -> void:
	target_alpha_multiplier = target
	transition_speed = 1.0 / max(transition_time, 0.001)
