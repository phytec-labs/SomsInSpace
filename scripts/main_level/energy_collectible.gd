# energy_collectible.gd
extends GameObject
class_name EnergyCollectible

@export var energy_value: float = 10.0
@export var rotation_speed: float = 10.0
@export var scale_variation: float = 0.3
@export var fall_speed: float = 100.0  # Speed at which collectible falls
@export var collect_sound: AudioStream = preload("res://audio/retro-coin-1.mp3")
@export var sound_pitch_variation: float = 0.1
var audio_player: AudioStreamPlayer2D

var base_scale: float
var time_alive: float = 0.0

func _ready() -> void:
	super._ready()
	
	# Initialize audio player
	audio_player = AudioStreamPlayer2D.new()
	audio_player.name = "CollectAudioPlayer"
	add_child(audio_player)
	
	# Try to load a default sound if none is assigned
	if not collect_sound:
		# Try to load a default sound (adjust the path to your actual audio file)
		if ResourceLoader.exists("res://audio/collect.mp3"):
			collect_sound = load("res://audio/collect.mp3")
	
	if collect_sound:
		audio_player.stream = collect_sound

	if sprite:
		print("Collectible sprite visibility: ", sprite.visible)
		print("Collectible sprite modulate: ", sprite.modulate)
		print("Collectible sprite scale: ", sprite.scale)
	else:
		print("Sprite node not found in collectible!")
		
func _process(delta: float) -> void:
	if is_active:
		# Move downwards
		position.y += fall_speed * delta
		
		# Animate the width for 3D effect
		time_alive += delta
		var scale_factor = abs(cos(time_alive * rotation_speed))
		scale.x = base_scale * scale_factor
		
		# Check if off-screen
		check_if_offscreen()

# Override initialize to add some debugging
func initialize(spawn_position: Vector2) -> void:
	base_scale = scale.x
	super.initialize(spawn_position)
	print("Energy collectible spawned at position: ", spawn_position)

func handle_player_collision() -> void:
	# Play collect sound before being destroyed
	if audio_player and audio_player.stream:
		# Detach the audio player so it continues playing after the collectible is gone
		remove_child(audio_player)
		get_parent().add_child(audio_player)
		
		# Position at the collectible's last position
		audio_player.global_position = global_position
		
		# Add pitch variation for more natural sound
		audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
		audio_player.play()
		
		# Set up auto-deletion after playing
		audio_player.finished.connect(audio_player.queue_free)
	
	# Could add visual effects here too (sparkles, etc.)
	print("Energy collectible collected! Points: ", points)
	super.handle_player_collision()
