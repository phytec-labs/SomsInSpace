# missile_pickup.gd
# Missile upgrade: player.activate_missiles(GameConfig.missile_duration) (8 s;
# re-collecting refreshes it): while it lasts and the player fires, a pair of
# homing sidewinder missiles leaves the wing guns every
# player.missile_interval (see scripts/effects/player_missile.gd). Always
# dropped by the zeppelin mini-boss; rare from the pickup table
# (ZoneDefinition.pickup_weight_missile: upper atmosphere and space). At most
# one on screen from the table (SpawnManager). Pooled like the energy
# collectible; the effect is applied by main_level.gd _on_object_collected()
# via get_pickup_type().
#
# Icon (scenes/collectibles/missile_pickup.tscn), by design partly code-drawn:
# a dark rounded tile (Polygon2D) with an orange Line2D border, with the
# sidewinder art (sprites/side_winder_missile_1.png, `Missile` Sprite2D at
# scale 0.087 = ~44 px long, tilted 45 deg, nose up-right, shifted 2.5 px
# toward the nose so the fins and nose both keep 3.5 px from the border's inner
# edge; self_modulate 1.5 brightens it in the icon only) inside, all under
# an untextured Sprite2D (GameObject's `sprite`, shown / hidden with the
# pickup), pulsed in code (no sheet). See docs/ART_SWAP_TRACKER.md.
extends EnergyCollectible

## Icon pulse (scale +-amount at speed rad/s; the icon has no animation frames)
@export var pulse_amount: float = 0.08
@export var pulse_speed: float = 6.0
@onready var _icon: Node2D = get_node_or_null("Sprite2D")

func get_pickup_type() -> StringName:
	return &"missile"

func _process(delta: float) -> void:
	super._process(delta)
	if is_active and _icon:
		var s := 1.0 + pulse_amount * sin(time_alive * pulse_speed)
		_icon.scale = Vector2(s, s)
