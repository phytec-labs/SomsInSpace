# game_config.gd
# Top-level game tuning: scroll speed, countdown and the ordered zone list.
class_name GameConfig
extends Resource

const ZoneDefinitionScript := preload("res://scripts/data/zone_definition.gd")

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
@export var max_active_obstacles: int = 150
## Optional rule: a damaging hit (obstacle contact or enemy shot) also drops
## the player's weapon one tier (min tier 1).
@export var lose_weapon_tier_on_hit: bool = false

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
