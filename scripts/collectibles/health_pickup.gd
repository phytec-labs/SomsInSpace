# health_pickup.gd
# Health cell: restores GameConfig.health_pickup_amount (25) health, clamped
# to the ship's max (main_level.gd heal()). Rolled by the SpawnManager's
# pickup table (never at full health) and dropped by the blimp and by the
# boss at its phase changes. Pooled like the energy collectible; the effect is
# applied by main_level.gd _on_object_collected() via get_pickup_type().
#
# Art: AnimatedSprite2D with sprites/health_pickup.tres: the 5-frame
# "breathing" canister in sprites/health_pickup_sheet.png (5 x 256 px cells,
# each centered on the red cross; built by tools/resize_art.gd from
# art_archive/masters/health_pickup_sprite_sheet.png), looping 0-1-2-3-4 at
# 8 fps, scale 0.3675 (25% under the first 0.49): the canister is ~42 px wide
# in the smallest frames and ~54 px in the middle one (intended pulse); with
# sparkles the icon spans up to ~75x84 px. Collision circle r 21 (was 28,
# shrunk with the art so it matches the smallest canister). No coin spin
# (spin = false in the scene). GameObject restarts the animation from frame 0
# on every spawn.
extends EnergyCollectible

func get_pickup_type() -> StringName:
	return &"health"
