extends Node2D

class Star:
	var position: Vector2
	var size: float
	var flicker_speed: float
	var time_offset: float
	var base_alpha: float
	var color: Color

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

@export var star_count: int = 100
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
@export var shooting_star_chance: float = 0.02
@export var shooting_star_speed: float = 500.0
@export var shooting_star_length: float = 30.0
@export var shooting_star_lifetime: float = 1.0

var current_alpha_multiplier: float = 0.0
var target_alpha_multiplier: float = 0.0
var transition_speed: float = 1.0

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
		var offset = rng.randf_range(0, PI * 2)
		var base_alpha = rng.randf_range(0.5, 1.0)

		var base_color = star_colors[rng.randi() % star_colors.size()]
		var varied_color = Color(
			clampf(base_color.r + rng.randf_range(-color_variation, color_variation), 0, 1),
			clampf(base_color.g + rng.randf_range(-color_variation, color_variation), 0, 1),
			clampf(base_color.b + rng.randf_range(-color_variation, color_variation), 0, 1)
		)

		stars.append(Star.new(pos, size, speed, offset, base_alpha, varied_color))

@export var scroll_speed: float = 50.0  # Add this at the top with other @export vars

func _process(delta):
	# Update alpha transition
	current_alpha_multiplier = lerp(current_alpha_multiplier, target_alpha_multiplier, delta * transition_speed)

	# Update star positions
	var viewport_size = get_viewport_rect().size
	for star in stars:
		star.position.y += scroll_speed * delta
		# Wrap stars to top when they go below screen
		if star.position.y > viewport_size.y:
			star.position.y = 0
			star.position.x = rng.randf_range(0, viewport_size.x)

	# Update shooting stars
	if target_alpha_multiplier > 0.8:  # Only spawn shooting stars in space
		update_shooting_stars(delta)

	queue_redraw()

func update_shooting_stars(delta: float) -> void:
	# Update existing shooting stars
	for i in range(shooting_stars.size() - 1, -1, -1):
		var shooting_star = shooting_stars[i]
		shooting_star.position += shooting_star.velocity * delta
		shooting_star.lifetime -= delta

		if shooting_star.lifetime <= 0:
			shooting_stars.remove_at(i)

	# Spawn new shooting stars
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
	# Draw regular stars
	for star in stars:
		var flicker = (sin(Time.get_ticks_msec() * 0.001 * star.flicker_speed + star.time_offset) + 1) * 0.5
		var alpha = star.base_alpha * (0.5 + 0.5 * flicker) * current_alpha_multiplier
		var star_color = star.color
		star_color.a = alpha
		draw_circle(star.position, star.size, star_color)

	# Draw shooting stars
	for shooting_star in shooting_stars:
		var fade = shooting_star.lifetime / shooting_star.max_lifetime * current_alpha_multiplier
		var tail_start = shooting_star.position
		var tail_end = shooting_star.position - shooting_star.velocity.normalized() * shooting_star.length
		draw_line(tail_start, tail_end, Color(1, 1, 1, fade), 2.0)

func set_star_visibility(target: float, transition_time: float = 1.0) -> void:
	target_alpha_multiplier = target
	transition_speed = 1.0 / max(transition_time, 0.001)
