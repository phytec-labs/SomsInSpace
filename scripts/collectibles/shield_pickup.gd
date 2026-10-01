# shield_pickup.gd
# Shield bubble: player.activate_shield(GameConfig.shield_duration) (8 s;
# re-collecting refreshes it). At most one on screen (SpawnManager). Pooled
# like the energy collectible; the effect is applied by main_level.gd
# _on_object_collected() via get_pickup_type().
#
# Art: sprites/shield_dome_1.png (518x512) on the Sprite2D at 0.1072
# (~55 px wide), the same dome as the player's shield bubble.
extends EnergyCollectible

func get_pickup_type() -> StringName:
	return &"shield"
