# bomb_pickup.gd
# Screen-clear bomb: fires on pickup (main_level.gd detonate_bomb()): white
# flash, big shake, every ordinary obstacle on screen destroyed (points and
# combo as normal kills), the boss, the zeppelin and the mini-boss UFO
# (Obstacle.bomb_resistant) take GameConfig.bomb_boss_damage, enemy
# projectiles on screen removed. At most one on screen (SpawnManager); never
# rolled in the orbit/boss zone (weight 0). Pooled like the energy collectible.
#
# Art: AnimatedSprite2D with sprites/bomb_pickup.tres: the 6-frame loop in
# sprites/bomb_pickup_sheet.png (6 x 256 px cells, each centered on the round
# body; built by tools/resize_art.gd from
# art_archive/masters/bomb_collectible_2.png): the core heats up, steam vents
# (frame 3 drawn 1.12x larger, intended), then it settles; looping at 8 fps,
# scale 0.393 (body ~50 px on screen in the resting frames 0/5, ~56 px in
# frame 3; fuse flame and steam reach further). Collision circle r 25 (the
# body). No coin spin (spin = false in the scene). GameObject restarts the
# animation from frame 0 on every spawn.
extends EnergyCollectible

func get_pickup_type() -> StringName:
	return &"bomb"
