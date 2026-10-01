# shield_pickup.gd
# Shield bubble: player.activate_shield(GameConfig.shield_duration) (8 s;
# re-collecting refreshes it). At most one on screen (SpawnManager). Pooled
# like the energy collectible; the effect is applied by main_level.gd
# _on_object_collected() via get_pickup_type().
#
# Art: AnimatedSprite2D with sprites/shield_icon.tres: the 5-frame glow pulse
# in sprites/shield_icon_sheet.png (5 x 256 px cells, sphere centered and the
# same size in every cell; built by tools/resize_art.gd from
# art_archive/masters/shield_icon_sprite_sheet.png), looping 0-1-2-3-4 at
# 8 fps, scale 0.3 (~55 px sphere on screen; the glow reaches ~72 px). The art
# carries its own glow: no shader material. No coin spin (spin = false in the
# scene): scale.x stays constant. GameObject restarts the animation from frame
# 0 on every spawn (stop() on deactivate, play() in initialize()).
extends EnergyCollectible

func get_pickup_type() -> StringName:
	return &"shield"
