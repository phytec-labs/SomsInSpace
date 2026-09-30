# wave_definition.gd
# A named sequence of WaveGroups. Once every group has spawned and all of
# them are cleared, WaveManager waits `completion_delay` seconds (scaled by
# the zone's beat multiplier) before the zone's next wave.
class_name WaveDefinition
extends Resource

const WaveGroupScript := preload("res://scripts/data/wave_group.gd")

@export var name: String = ""
@export var groups: Array[WaveGroupScript] = []
@export var completion_delay: float = 1.0
