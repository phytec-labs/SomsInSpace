# energy_collectible.gd
# The energy coin (scenes/collectibles/energy_collectible_1.tscn, 5 points,
# flat: no combo) and the base of every pickup (health, shield, bomb,
# missile, weapon upgrade). main_level.gd awards `points` on collect; for the
# coin (pickup type energy) it also pops a gold "+5" and the coin pop
# (scenes/effects/coin_pop.tscn).
#
# The coin is drawn by shaders/coin.gdshader on the untextured Sprite2D's
# Coin ColorRect (no texture art; see docs/ART_SWAP_TRACKER.md, "Coin
# look"); this script feeds its spin_angle and twinkle_phase. Scenes
# without that node keep
# the old width-flip spin (`spin`).
extends GameObject
class_name EnergyCollectible

@export var energy_value: float = 10.0
@export var rotation_speed: float = 10.0
@export var scale_variation: float = 0.3
@export var fall_speed: float = 100.0  # Speed at which collectible falls
@export var collect_sound: AudioStream = preload("res://audio/retro-coin-1.mp3")
@export var sound_pitch_variation: float = 0.1
# Width-flip "coin spin" (scale.x follows |cos(time_alive * rotation_speed)|);
# off for pickups with their own animation (shield pickup), whose scale.x
# then stays at base_scale. Ignored when the scene has the procedural coin
# (Sprite2D/Coin with shaders/coin.gdshader): the shader draws that spin.
@export var spin: bool = true
## Procedural coin only: spin speed (rad/s; one turn = TAU) and its random
## spread per spawn (0.15 = +-15%), so a field of coins never turns in step
@export var coin_spin_speed: float = 4.5
@export var coin_spin_speed_variation: float = 0.15
## Procedural coin only: seconds between twinkles (the shader plays one over
## the first twinkle_len of each cycle, ~0.25 s, skipped if the coin is
## edge-on then); ~2.6 turns at coin_spin_speed. Random offset per spawn.
@export var coin_twinkle_period: float = 3.6

var base_scale: float = -1.0  # Captured on first spawn; scale.x is animated
var time_alive: float = 0.0

# Procedural coin (energy collectible scene): its ShaderMaterial is local to
# each instance (resource_local_to_scene), so every coin gets its own
# spin_angle and twinkle_phase uniforms, driven here from time_alive
# (pause-safe) with a random spin phase and speed and a random twinkle offset
# rolled on every spawn (pooled instances included). Both stay small (wrapped)
# for mediump precision in the shader.
@onready var _coin_material: ShaderMaterial = _find_coin_material()
var coin_phase: float = 0.0
var coin_speed: float = 0.0
var coin_twinkle_offset: float = 0.0

func _find_coin_material() -> ShaderMaterial:
	var coin := get_node_or_null("Sprite2D/Coin") as CanvasItem
	return coin.material as ShaderMaterial if coin else null

# Current spin angle of the procedural coin (radians, wrapped to 0..TAU)
func get_coin_spin_angle() -> float:
	return fposmod(coin_phase + time_alive * coin_speed, TAU)

# Current twinkle cycle position of the procedural coin (0..1)
func get_coin_twinkle_phase() -> float:
	return fposmod(coin_twinkle_offset + time_alive / coin_twinkle_period, 1.0)

# Kind of pickup, read by main_level.gd (effect on collect) and the
# SpawnManager (on-screen limits): energy, health, shield, bomb, weapon
func get_pickup_type() -> StringName:
	return &"energy"

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
		if _coin_material:
			_coin_material.set_shader_parameter(&"spin_angle", get_coin_spin_angle())
			_coin_material.set_shader_parameter(&"twinkle_phase", get_coin_twinkle_phase())
		elif spin:
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
	if _coin_material:
		coin_phase = randf() * TAU
		coin_speed = coin_spin_speed * randf_range(1.0 - coin_spin_speed_variation,
			1.0 + coin_spin_speed_variation)
		coin_twinkle_offset = randf()
		_coin_material.set_shader_parameter(&"spin_angle", coin_phase)
		_coin_material.set_shader_parameter(&"twinkle_phase", coin_twinkle_offset)
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
