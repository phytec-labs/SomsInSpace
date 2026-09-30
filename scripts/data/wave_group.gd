# wave_group.gd
# One group inside a wave: `count` formations of type `formation`, spawned
# `enemy_delay` seconds apart, followed by `delay` seconds before the next group.
# With `scene_override` set, the group spawns `count` single instances of that
# scene instead of formations (e.g. a mini-boss or a deliberate UFO).
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

@export_group("Specific Enemies")
## Formation members are all this scene instead of random picks from the
## zone's obstacle_scenes (e.g. a SWARM of drones). Ignored when
## scene_override is set.
@export var formation_scene: PackedScene
## When set, the group ignores `formation` and spawns `count` single
## instances of this scene (one per enemy_delay tick, no ramp count bonus),
## through SpawnManager.spawn_scene() (respects the obstacle cap).
@export var scene_override: PackedScene
## Spawn this group at most once per zone visit: once something from it has
## spawned, later loops of the zone's waves skip the group (a capped spawn
## that produced nothing does not count, so it is retried next loop).
@export var one_shot: bool = false
