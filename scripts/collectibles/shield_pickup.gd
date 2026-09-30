# shield_pickup.gd
# Shield bubble: player.activate_shield(GameConfig.shield_duration) (8 s;
# re-collecting refreshes it). At most one on screen (SpawnManager). Pooled
# like the energy collectible; the effect is applied by main_level.gd
# _on_object_collected() via get_pickup_type().
#
# PLACEHOLDER_ART: scenes/collectibles/shield_pickup.tscn draws the icon with
# children of the (texture-less) Sprite2D: a translucent cyan "Fill" disk, a
# cyan "Ring" Line2D and a "Highlight" arc. Replace them with a 256x256
# transparent PNG as the Sprite2D texture (scale ~0.22).
extends EnergyCollectible

func get_pickup_type() -> StringName:
	return &"shield"
