# zone_definition.gd
# All tuning for one altitude zone (ground, atmosphere, ...).
class_name ZoneDefinition
extends Resource

const WaveDefinitionScript := preload("res://scripts/data/wave_definition.gd")
const FormationSettingsScript := preload("res://scripts/data/formation_settings.gd")

## Zone id; AtmosphereManager / CloudManager / GameHUD match on these strings
## ("ground", "atmosphere", "upper_atmosphere", "space", "orbit").
@export var id: StringName = &""
@export var display_name: String = ""
## Compact name for the HUD zone bar (empty = use display_name).
@export var short_name: String = ""
## Height (m) at which this zone starts.
@export var start_height: int = 0

@export_group("Features")
## Spawn a weapon upgrade pickup (one tier up) once per run when this zone
## is entered, unless the player's weapon is already at max tier.
@export var spawns_weapon_upgrade: bool = false
## CloudManager spawns clouds while this zone is active.
@export var has_clouds: bool = false
## Height stops increasing while this zone is active (e.g. the boss zone).
@export var freezes_height: bool = false
## Boss spawned (once) when this zone is entered; null = no boss.
@export var boss_scene: PackedScene

@export_group("Appearance")
## Background color the AtmosphereManager wipes to when this zone is entered.
@export var background_color: Color = Color(0.53, 0.81, 0.92, 1.0)
## Starfield opacity in this zone (0 = no stars, 1 = full).
@export_range(0.0, 1.0) var star_visibility: float = 0.0

@export_group("Spawning")
## Random obstacle pool for legacy SpawnManager.spawn_obstacle() callers only;
## wave groups always name their own enemy_scene.
@export var obstacle_scenes: Array[PackedScene] = []
## Waves played in order, looping; pacing ramps up over time (see Difficulty Ramp).
@export var waves: Array[WaveDefinitionScript] = []
@export var formation_settings: FormationSettingsScript
## Formations allowed on screen at once in this zone (WaveManager holds the
## next group while this many are alive); 0 = GameConfig.max_formations_on_screen.
## Raising it only matters for waves whose groups overlap (AFTER_DELAY).
@export var max_formations_on_screen: int = 0
## Multipliers applied to SpawnManager's base collectible time / chance.
@export var collectible_time_scale: float = 1.0
@export var collectible_chance_scale: float = 1.0

@export_group("Mini-boss")
## Self-moving mini-boss (e.g. the blimp) the WaveManager spawns once per
## visit of this zone, outside the wave list, at the top center (the
## `hover_top` path start) with a telegraph marker first; null = none. It is
## anchored to the zone's weapon upgrade (see below), so it always meets a
## freshly upgraded weapon.
@export var miniboss_scene: PackedScene
## Seconds from collecting this zone's weapon upgrade to the mini-boss spawn
## (the telegraph shows during the last telegraph_seconds of it).
@export var miniboss_delay_after_upgrade: float = 2.5
## Zone time (s since the zone was entered) at which the mini-boss spawns
## anyway: the upgrade was not collected by then, or the zone spawned none
## (weapon already at max tier). Whichever comes first wins. 0 = no
## fallback (only the upgrade triggers it).
@export var miniboss_fallback_zone_time: float = 18.0
## While the mini-boss is alive the wave sequencer finishes the group it is
## releasing but starts no new group (formations already flying keep going);
## it resumes a short beat after the mini-boss died or left.
@export var miniboss_holds_waves: bool = true
## Longest hold (s after the mini-boss spawned): past it the sequencer
## releases groups again alongside a mini-boss that is still alive (it still
## counts toward the formations on screen). 0 = hold until it is gone.
@export var miniboss_hold_max_seconds: float = 8.0

@export_group("Pickup Weights")
## Relative odds of each pickup type when SpawnManager.spawn_collectible()
## fires (the collectible timer). Guarantees applied on top: at most one
## shield and one bomb on screen, and no health cell at full health (both
## re-rolled as energy).
@export var pickup_weight_energy: float = 100.0
@export var pickup_weight_health: float = 0.0
@export var pickup_weight_shield: float = 0.0
@export var pickup_weight_bomb: float = 0.0

@export_group("Obstacle Movement Pattern Weights")
## Random movement patterns for legacy spawn_obstacle() / boss minions only
## (wave formations are driven by their EntryPath).
@export var pattern_weight_linear: float = 0.5
@export var pattern_weight_sine: float = 0.3
@export var pattern_weight_zigzag: float = 0.2

@export_group("Difficulty")
## Multiplies the health of every obstacle spawned in this zone (formation
## members, scene_override singles, asteroid pieces, boss minions; not the
## boss itself). Enemies have 10 base health (drones 5, mines 8, asteroids
## 30/15/6 by size, UFO 80, blimp 270) vs 10 damage per tier-1 shot.
@export var enemy_health_multiplier: float = 1.0

@export_group("Difficulty Ramp")
## Seconds spent in this zone per ramp level (level = int(zone_time / this)).
## The ramp adds speed, never bodies: counts stay as authored.
@export var ramp_interval_seconds: float = 25.0
## Each ramp level multiplies path_speed and descend speeds by this
## (compounding)...
@export var ramp_speed_multiplier: float = 1.1
## ...up to this.
@export var max_speed_multiplier: float = 1.6
## Each ramp level multiplies beats, delays and completion delays by this
## (compounding)...
@export var ramp_beat_multiplier: float = 0.9
## ...down to this.
@export var min_beat_multiplier: float = 0.5

# Name shown on the HUD zone bar
func get_short_name() -> String:
	return short_name if not short_name.is_empty() else display_name

# Formation speed multiplier for the given ramp level (0 = just entered)
func get_speed_multiplier(level: int) -> float:
	return minf(max_speed_multiplier, pow(ramp_speed_multiplier, maxi(level, 0)))

# Beat / delay multiplier for the given ramp level
func get_beat_multiplier(level: int) -> float:
	return maxf(min_beat_multiplier, pow(ramp_beat_multiplier, maxi(level, 0)))

# Ramp level after `seconds` spent in this zone
func get_ramp_level(seconds: float) -> int:
	if ramp_interval_seconds <= 0.0:
		return 0
	return int(maxf(seconds, 0.0) / ramp_interval_seconds)

# Pattern weights in the order [linear, sine, zigzag]
func get_pattern_weights() -> Array[float]:
	return [pattern_weight_linear, pattern_weight_sine, pattern_weight_zigzag]

# Pickup weights in the order [energy, health, shield, bomb]
func get_pickup_weights() -> Array[float]:
	return [pickup_weight_energy, pickup_weight_health, pickup_weight_shield, pickup_weight_bomb]
