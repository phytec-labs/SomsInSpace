# wave_group.gd
# One group inside a wave: `count` formations of type `formation`, spawned
# `enemy_delay` seconds apart, followed by `delay` seconds before the next group.
class_name WaveGroup
extends Resource

# Preloaded (not referenced by class_name) so this works even before the
# editor has rebuilt the global class cache.
const FormationManagerScript := preload("res://scripts/main_level/formation_manager.gd")

@export var formation: FormationManagerScript.FormationType = FormationManagerScript.FormationType.LINE
@export var count: int = 1
## Seconds to wait after this group's last formation before the next group.
@export var delay: float = 1.0
## Seconds before each formation of this group is spawned.
@export var enemy_delay: float = 0.5
## Where each formation may spawn: "top", "left", "right" or "bottom"
## (one is picked at random per formation).
@export var spawn_positions: Array[StringName] = [&"top"]
