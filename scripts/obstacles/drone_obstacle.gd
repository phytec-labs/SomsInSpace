# drone_obstacle.gd
# Small, fragile drone that comes in SWARM formations (see FormationManager
# SWARM and WaveGroup.enemy_scene). No shooting; all tuning is in the
# scene's exports (health, damage, points, base_speed).
#
# Art: sprites/drone_1.png (512x512, master in art_archive/masters/; claws
# down toward the player) on a Sprite2D at 0.0784 (~40 px on screen); CircleShape2D r 15 over the body and
# rotor hubs (claw and rotor tips left out).
extends Obstacle
class_name DroneObstacle

func _ready() -> void:
	super._ready()
	can_shoot = false
