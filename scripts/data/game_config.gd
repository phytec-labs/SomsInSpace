# game_config.gd
# Top-level game tuning: scroll speed, countdown, the ordered zone list and
# the selectable ships.
class_name GameConfig
extends Resource

const ZoneDefinitionScript := preload("res://scripts/data/zone_definition.gd")
const ShipDefinitionScript := preload("res://scripts/data/ship_definition.gd")

## Zones ordered by ascending start_height (the first should start at 0).
@export var zones: Array[ZoneDefinitionScript] = []
## Height gained per second (m/s).
@export var scroll_speed: float = 100.0
## Seconds of "3, 2, 1" before launch.
@export var countdown_time: float = 3.0
## Height represented by the full width of the HUD zone progress bar
## (normally the last zone's start_height, i.e. where the boss appears).
@export var progress_bar_max_height: int = 13500
## Safety valve: SpawnManager skips obstacle spawns while this many are
## active (0 disables the cap).
@export var max_active_obstacles: int = 60
## WaveManager holds the next group while this many formations are alive.
@export var max_formations_on_screen: int = 3
## Seconds the spawn telegraph marker shows before a group spawns.
@export var telegraph_seconds: float = 0.5
## Optional rule: a damaging hit (obstacle contact or enemy shot) also drops
## the player's weapon one tier (min tier 1).
@export var lose_weapon_tier_on_hit: bool = false
## Selectable player ships, in ship select order (the first is the default).
@export var ships: Array[ShipDefinitionScript] = []
## Short tick when a shot hits an enemy without killing it (Obstacle
## hit_sound, rate limited). Off = only kills make a sound.
@export var enemy_hit_sound_enabled: bool = true

@export_group("Pickups")
## Pickup scenes rolled by SpawnManager.spawn_collectible() with each zone's
## pickup_weight_* table (see ZoneDefinition). All extend EnergyCollectible
## and are pooled through the SpawnManager like the energy collectible.
@export var energy_collectible_scene: PackedScene
@export var health_pickup_scene: PackedScene
@export var shield_pickup_scene: PackedScene
@export var bomb_pickup_scene: PackedScene
## Health restored by a health cell (clamped to the ship's max_health).
@export var health_pickup_amount: float = 25.0
## Seconds a shield bubble lasts (re-collecting refreshes it to this).
@export var shield_duration: float = 8.0
## Drain (UFO beam) damage multiplier while shielded (the beam is escapable,
## so the shield only halves it).
@export_range(0.0, 1.0) var shield_drain_factor: float = 0.5
## Damage a screen-clear bomb deals to a boss (other obstacles on screen are
## destroyed outright).
@export var bomb_boss_damage: float = 150.0
## Damage a shielded player's contact deals to obstacles that survive rams
## (boss, blimp), once per their contact hit interval. Ordinary obstacles
## rammed while shielded are destroyed and award their kill points.
@export var shield_ram_damage: float = 40.0

# Returns the highest zone whose start_height is <= height (or the first zone)
func get_zone_for_height(height: float) -> ZoneDefinitionScript:
	var result: ZoneDefinitionScript = zones[0] if not zones.is_empty() else null
	for zone in zones:
		if zone and height >= zone.start_height:
			result = zone
	return result

# Index of the zone with the given id, or -1
func get_zone_index(id: StringName) -> int:
	for i in zones.size():
		if zones[i] and zones[i].id == id:
			return i
	return -1

func get_zone(id: StringName) -> ZoneDefinitionScript:
	var index := get_zone_index(id)
	return zones[index] if index >= 0 else null
