# shield_pickup.gd
# Shield bubble: player.activate_shield(GameConfig.shield_duration) (8 s;
# re-collecting refreshes it). At most one on screen (SpawnManager). Pooled
# like the energy collectible; the effect is applied by main_level.gd
# _on_object_collected() via get_pickup_type().
#
# Art: sprites/shield_dome_1.png (634x634: 512 px sphere + 12% margin) on the
# Sprite2D at 0.1148 (~55 px visible sphere), the same sphere as the player's
# shield bubble, with shaders/shield_bubble.gdshader (interior_strength 0.8 so
# the small icon stays readable).
extends EnergyCollectible

func get_pickup_type() -> StringName:
	return &"shield"
