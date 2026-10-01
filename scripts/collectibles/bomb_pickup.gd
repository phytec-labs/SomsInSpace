# bomb_pickup.gd
# Screen-clear bomb: fires on pickup (main_level.gd detonate_bomb()): white
# flash, big shake, every non-boss obstacle on screen destroyed (points and
# combo as normal kills), the boss takes GameConfig.bomb_boss_damage, enemy
# projectiles on screen removed. At most one on screen (SpawnManager); never
# rolled in the orbit/boss zone (weight 0). Pooled like the energy collectible.
#
# Art: sprites/bomb_collectible_1.png (560x512, from art_archive/masters/) on
# the Sprite2D at 0.1 (~54x50 px on screen), offset (6, -6) so the round body
# (not the fuse spark at the top right) sits on the pickup's center and spin axis.
extends EnergyCollectible

func get_pickup_type() -> StringName:
	return &"bomb"
