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
