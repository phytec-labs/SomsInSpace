# zone_definition.gd
# All tuning for one altitude zone (ground, atmosphere, ...).
class_name ZoneDefinition
extends Resource

const WaveDefinitionScript := preload("res://scripts/data/wave_definition.gd")
const FormationSettingsScript := preload("res://scripts/data/formation_settings.gd")

## Zone id; AtmosphereManager / CloudManager / GameHUD match on these strings
## ("ground", "atmosphere", "upper_atmosphere", "space").
@export var id: StringName = &""
@export var display_name: String = ""
## Height (m) at which this zone starts.
@export var start_height: int = 0

@export_group("Features")
## Spawn the one-per-run weapon upgrade when this zone is entered.
@export var spawns_weapon_upgrade: bool = false
## CloudManager spawns clouds while this zone is active.
@export var has_clouds: bool = false

@export_group("Spawning")
## Obstacle scenes the zone's formations are built from (picked at random).
@export var obstacle_scenes: Array[PackedScene] = []
## Waves played in order, looping; pacing ramps up over time (see Difficulty Ramp).
@export var waves: Array[WaveDefinitionScript] = []
@export var formation_settings: FormationSettingsScript
## Multipliers applied to SpawnManager's base collectible time / chance.
@export var collectible_time_scale: float = 1.0
@export var collectible_chance_scale: float = 1.0

@export_group("Obstacle Movement Pattern Weights")
@export var pattern_weight_linear: float = 0.5
@export var pattern_weight_sine: float = 0.3
@export var pattern_weight_zigzag: float = 0.2

@export_group("Difficulty Ramp")
## Seconds spent in this zone per ramp level (level = int(zone_time / this)).
@export var ramp_interval_seconds: float = 30.0
## Each ramp level multiplies group delay, enemy_delay and wave
## completion_delay by this (compounding)...
@export var ramp_delay_multiplier: float = 0.9
## ...down to this lower bound.
@export var min_delay_multiplier: float = 0.6
## One extra formation per group every this many ramp levels...
@export var levels_per_count_bonus: int = 4
## ...up to this many extra formations per group.
@export var max_count_bonus: int = 1

# Delay multiplier for the given ramp level (0 = just entered the zone)
func get_delay_multiplier(level: int) -> float:
	return maxf(min_delay_multiplier, pow(ramp_delay_multiplier, maxi(level, 0)))

# Extra formations per group for the given ramp level
func get_count_bonus(level: int) -> int:
	if levels_per_count_bonus <= 0:
		return 0
	return mini(max_count_bonus, maxi(level, 0) / levels_per_count_bonus)

# Ramp level after `seconds` spent in this zone
func get_ramp_level(seconds: float) -> int:
	if ramp_interval_seconds <= 0.0:
		return 0
	return int(maxf(seconds, 0.0) / ramp_interval_seconds)

# Pattern weights in the order [linear, sine, zigzag]
func get_pattern_weights() -> Array[float]:
	return [pattern_weight_linear, pattern_weight_sine, pattern_weight_zigzag]
