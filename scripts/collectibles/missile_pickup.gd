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
# PLACEHOLDER_ART: scenes/collectibles/missile_pickup.tscn draws the icon with
# primitives: a dark rounded tile (Polygon2D) with an orange Line2D border and
# a small white/cyan missile silhouette (Polygon2D) pointing up-right, all
# under an untextured Sprite2D (GameObject's `sprite`, shown / hidden with the
# pickup), pulsed in code (no sheet). Replace that Sprite2D with an AnimatedSprite2D using a 5-frame
# sheet like the shield / health icons (2172x724 master strip, repacked to
# 256 px cells by tools/resize_art.gd) or a Sprite2D with a single 512 px
# icon, see docs/ART_SWAP_TRACKER.md.
extends EnergyCollectible

## Icon pulse (scale +-amount at speed rad/s; the placeholder has no animation)
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
