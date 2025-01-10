extends PathFollow2D

@export var speed = 100  # Adjust this to control ship speed
@export var rotation_speed = 2.0  # Adjust this to control ship rotation

func _ready():
	# Start at the beginning of the path
	progress_ratio = 0.0

func _process(delta):
	# Move along the path
	progress_ratio += (speed * delta) / get_parent().curve.get_baked_length()
	
	# Loop back to start when we reach the end
	if progress_ratio >= 1.0:
		progress_ratio = 0.0
	
	# Rotate ship to follow path direction
	if rotation_speed > 0:
		var next_pos = get_parent().curve.sample_baked(progress + 1)
		var current_pos = position
		var direction = (next_pos - current_pos).normalized()
		rotation = lerp_angle(rotation, direction.angle(), rotation_speed * delta)
