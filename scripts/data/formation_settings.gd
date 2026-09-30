# formation_settings.gd
# Per-zone formation tuning used by FormationManager.create_path_formation().
class_name FormationSettings
extends Resource

## Member spacing (px) for groups whose WaveGroup.spread is 0.
@export var default_spread: float = 90.0

@export_group("Swarm")
## SWARM members are scattered within this radius (px) of the formation
## center (WaveGroup.spread overrides it when > 0). 165 keeps 6-8 drones
## (~40 px) >= ~48 px apart with the jitter below.
@export var swarm_radius: float = 165.0
## The swarm sways side to side around its path with this amplitude (px)
## and angular frequency (rad/s).
@export var swarm_sine_amplitude: float = 50.0
@export var swarm_sine_frequency: float = 1.5
## Each member orbits its own offset with this radius (px) and base angular
## speed (rad/s, varied per member by +/- swarm_jitter_speed_variation).
@export var swarm_jitter_radius: float = 6.0
@export var swarm_jitter_speed: float = 4.0
@export_range(0.0, 1.0) var swarm_jitter_speed_variation: float = 0.4
