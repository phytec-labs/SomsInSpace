# wave_definition.gd
# A named sequence of WaveGroups, followed by `completion_delay` seconds
# before the zone's next wave starts.
class_name WaveDefinition
extends Resource

const WaveGroupScript := preload("res://scripts/data/wave_group.gd")

@export var name: String = ""
@export var groups: Array[WaveGroupScript] = []
@export var completion_delay: float = 2.0
