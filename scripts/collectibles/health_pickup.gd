# health_pickup.gd
# Health cell: restores GameConfig.health_pickup_amount (25) health, clamped
# to the ship's max (main_level.gd heal()). Rolled by the SpawnManager's
# pickup table (never at full health) and dropped by the blimp and by the
# boss at its phase changes. Pooled like the energy collectible; the effect is
# applied by main_level.gd _on_object_collected() via get_pickup_type().
#
# PLACEHOLDER_ART: scenes/collectibles/health_pickup.tscn draws the icon with
# Polygon2D/Line2D children of the (texture-less) Sprite2D: a dark rounded
# square "Backing" + green "Border" and a green "Cross". Replace them with a
# 256x256 transparent PNG as the Sprite2D texture (scale ~0.22).
extends EnergyCollectible

func get_pickup_type() -> StringName:
	return &"health"
