# energy_collectible.gd
extends GameObject
class_name EnergyCollectible

@export var energy_value: float = 10.0
@export var rotation_speed: float = 10.0
@export var scale_variation: float = 0.3
@export var fall_speed: float = 100.0  # Speed at which collectible falls
@export var collect_sound: AudioStream = preload("res://audio/retro-coin-1.mp3")
@export var sound_pitch_variation: float = 0.1

var base_scale: float = -1.0  # Captured on first spawn; scale.x is animated
var time_alive: float = 0.0

func _ready() -> void:
	super._ready()

	# Try to load a default sound if none is assigned
	if not collect_sound:
		# Try to load a default sound (adjust the path to your actual audio file)
		if ResourceLoader.exists("res://audio/collect.mp3"):
			collect_sound = load("res://audio/collect.mp3")

func _process(delta: float) -> void:
	if is_active:
		# Move downwards (speed_multiplier lets subclasses fall slower/faster)
		position.y += fall_speed * speed_multiplier * delta

		# Animate the width for 3D effect
		time_alive += delta
		var scale_factor = abs(cos(time_alive * rotation_speed))
		scale.x = base_scale * scale_factor

		# Check if off-screen
		check_if_offscreen()

# Reset per-spawn state (collectibles are reused from the spawn manager's pool)
func initialize(spawn_position: Vector2) -> void:
	if base_scale < 0.0:
		base_scale = scale.x
	scale.x = base_scale
	time_alive = 0.0
	super.initialize(spawn_position)

func handle_player_collision() -> void:
	if is_being_collected:
		return

	# Play collect sound on a one-shot player owned by the current scene, so it
	# keeps playing after this collectible is deactivated or reused
	if collect_sound:
		var audio_player = AudioStreamPlayer2D.new()
		audio_player.stream = collect_sound
		# Add pitch variation for more natural sound
		audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
		audio_player.finished.connect(audio_player.queue_free)
		var scene = get_tree().current_scene
		(scene if scene else get_parent()).add_child(audio_player)
		audio_player.global_position = global_position
		audio_player.play()

	super.handle_player_collision()
