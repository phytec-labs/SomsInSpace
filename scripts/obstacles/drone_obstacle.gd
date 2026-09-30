# drone_obstacle.gd
# Small, fragile drone that comes in SWARM formations (see FormationManager
# SWARM and WaveGroup.enemy_scene). No shooting; all tuning is in the
# scene's exports (health, damage, points, base_speed).
#
# PLACEHOLDER_ART: scenes/obstacles/drone_obstacle.tscn AnimatedSprite2D uses
# the alien SpriteFrames (sprites/alien_1.tres) at ~0.45x, tinted cyan via
# `self_modulate`. Swap sprite_frames (and reset self_modulate to white) when
# the drone sheet arrives.
extends Obstacle
class_name DroneObstacle

func _ready() -> void:
	super._ready()
	can_shoot = false
