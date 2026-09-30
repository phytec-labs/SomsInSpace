# bomb_pickup.gd
# Screen-clear bomb: fires on pickup (main_level.gd detonate_bomb()): white
# flash, big shake, every non-boss obstacle on screen destroyed (points and
# combo as normal kills), the boss takes GameConfig.bomb_boss_damage, enemy
# projectiles on screen removed. At most one on screen (SpawnManager); never
# rolled in the orbit/boss zone (weight 0). Pooled like the energy collectible.
#
# PLACEHOLDER_ART: scenes/collectibles/bomb_pickup.tscn draws the icon with
# children of the (texture-less) Sprite2D: an orange "Body" disk with a
# "Shine", a grey "Cap", a brown "Fuse" Line2D and a yellow "Spark" star
# (flickered below). Replace them with a 256x256 transparent PNG as the
# Sprite2D texture (scale ~0.22) and drop the spark flicker.
extends EnergyCollectible

const SPARK_FLICKER_RATE := 12.0  # Toggles per second

@onready var _spark: CanvasItem = get_node_or_null("Sprite2D/Spark")

func get_pickup_type() -> StringName:
	return &"bomb"

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	if _spark:
		_spark.visible = true

func _process(delta: float) -> void:
	super._process(delta)
	# Spark flicker from the base class's time_alive accumulator (pause-safe)
	if is_active and _spark:
		_spark.visible = int(time_alive * SPARK_FLICKER_RATE) % 2 == 0
