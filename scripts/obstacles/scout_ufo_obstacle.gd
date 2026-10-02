# scout_ufo_obstacle.gd
# Scout saucer: a medium formation enemy for the space zone (it replaced the
# satellites there; see data/zones/space.tres "Minefield"). An ordinary pooled
# formation member flown by FormationManager: no beam, no hover state machine
# (that is the UFO mini-boss, ufo_obstacle.gd). Each shoot() fires a fan of
# fan_bullets shots spread fan_spread_degrees apart around straight down from
# the GunPoint under the hull, at fan_speed px/s (set per spawn; the pooled
# shot restores its authored speed / lifetime when it despawns). The wave
# group's fire pattern (VOLLEY) calls shoot() on every scout at once, so a V
# of three fires nine shots together.
#
# Health 50 base (x 3.0 in space = 150): no mini health bar (show_health_bar
# off: the bar is for the mini-bosses and the big hulls).
#
# Art: sprites/ufo_2.png, the teal-lit second-colour render of the mini-boss
# saucer (same canvas and silhouette), at 60% of the mini-boss's size (scale
# 0.1247, ~127 px wide); no hue_shift. See docs/ART_SWAP_TRACKER.md
# ("Scout saucer").
extends Obstacle

@export_group("Scout Fan")
## Shots per fan, and the angle (degrees) between neighbouring shots
@export var fan_bullets: int = 3
@export var fan_spread_degrees: float = 18.0
## Shot speed (px/s) and lifetime (s), set on each shot for its flight
@export var fan_speed: float = 360.0
@export var fan_lifetime: float = 4.0
@export_group("")

# Observability (tests / tuning): fans fired this spawn
var fans_fired: int = 0

func _ready() -> void:
	show_health_bar = false
	super._ready()

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	fans_fired = 0

# One fan from the first gun point (formation fire patterns call this)
func shoot() -> void:
	if not projectile_scene or not is_active or gun_points.is_empty():
		return
	var gun: Node2D = gun_points[0]
	var count := maxi(fan_bullets, 1)
	var parent := _get_effects_parent()
	for i in range(count):
		var angle := deg_to_rad((float(i) - float(count - 1) / 2.0) * fan_spread_degrees)
		var shot = ObjectPool.acquire(projectile_scene, parent)
		if shot == null:
			continue
		shot.speed = fan_speed
		shot.lifetime = fan_lifetime
		shot.initialize(gun.global_position, Vector2.DOWN.rotated(angle))
	fans_fired += 1
	if shoot_audio_player and shoot_audio_player.stream:
		shoot_audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
		shoot_audio_player.play()
