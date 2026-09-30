# formation_settings.gd
# Per-zone formation tuning used by FormationManager.create_formation().
class_name FormationSettings
extends Resource

const FormationManagerScript := preload("res://scripts/main_level/formation_manager.gd")

## Formation types considered valid for the zone (informational; waves pick
## their formation explicitly).
@export var allowed_formations: Array[FormationManagerScript.FormationType] = []
@export var min_spread: float = 50.0
@export var max_spread: float = 80.0
## Objects per formation are rolled in [min_objects, max_objects], capped by
## the formation type's own object count.
@export var min_objects: int = 2
@export var max_objects: int = 4
## Scales applied to the formation movement pattern (sine/zigzag/spiral).
@export var pattern_amplitude_scale: float = 1.0
@export var pattern_frequency_scale: float = 1.0

@export_group("Swarm")
## SWARM formations roll their member count here (the zone's
## min_objects / max_objects do not apply to swarms).
@export var swarm_min_objects: int = 5
@export var swarm_max_objects: int = 8
## Members are scattered within this radius (px) of the swarm center.
@export var swarm_radius: float = 70.0
## The swarm center swings side to side with this amplitude (px) and
## angular frequency (rad/s) while it descends.
@export var swarm_sine_amplitude: float = 170.0
@export var swarm_sine_frequency: float = 0.9
## Each member orbits its own offset with this radius (px) and base angular
## speed (rad/s, varied per member by +/- swarm_jitter_speed_variation).
@export var swarm_jitter_radius: float = 14.0
@export var swarm_jitter_speed: float = 4.0
@export_range(0.0, 1.0) var swarm_jitter_speed_variation: float = 0.4
