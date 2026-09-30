# wave_group.gd
# One formation inside a wave: `count` members of `enemy_scene` in shape
# `formation`, flying the EntryPath `path` (see docs/WAVE_DESIGN.md).
# WaveManager plays a wave's groups in order: optional telegraph marker, then
# the formation spawns (all members at once, at the path start), then the
# next group is released per `release`.
# With `scene_override` set, the group instead spawns `count` single
# self-moving instances of that scene (blimp, UFO, ...) with no formation/path.
class_name WaveGroup
extends Resource

# Preloaded (not referenced by class_name) so this works even before the
# editor has rebuilt the global class cache.
const FormationManagerScript := preload("res://scripts/main_level/formation_manager.gd")

## When the NEXT group may start.
enum Release {
	ON_CLEAR,     ## After every member of this group is dead or gone, plus beat_after
	AFTER_DELAY,  ## `delay` seconds after this group spawned (deliberate overlaps)
}

## Every member is this scene.
@export var enemy_scene: PackedScene
@export var formation: FormationManagerScript.FormationType = FormationManagerScript.FormationType.LINE
## Members in this formation (scene_override: number of single instances).
@export var count: int = 3
## Member spacing (px); 0 = the zone's FormationSettings.default_spread.
## SWARM: scatter radius (0 = FormationSettings.swarm_radius).
@export var spread: float = 0.0

@export_group("Path")
## EntryPath id (res://data/paths/<id>.tres).
@export var path: StringName = &"top_straight"
## Speed (px/s) along the path; 0 = the path's default_speed.
@export var path_speed: float = 0.0
## HOLD_THEN_DESCEND paths: seconds to hover; 0 = the path's hold_seconds.
@export var hold_seconds: float = 0.0
## Randomly mirror (50%) the path and formation about the screen center.
@export var mirror_allowed: bool = true
## Always mirror (e.g. the right half of a pincer); overrides mirror_allowed.
@export var force_mirror: bool = false

@export_group("Fire")
@export var fire_mode: FormationManagerScript.FireMode = FormationManagerScript.FireMode.NONE
## Seconds between volleys / ripples (VOLLEY, RIPPLE).
@export var fire_interval: float = 2.0

@export_group("Release")
@export var release: Release = Release.ON_CLEAR
## AFTER_DELAY: seconds after this group spawned before the next group.
@export var delay: float = 0.0
## ON_CLEAR: pause (s) after this group is cleared before the next group.
@export var beat_after: float = 0.6
## Show a warning marker at the entry point telegraph_seconds before spawning.
@export var telegraph: bool = true

@export_group("Specific Enemies")
## When set, the group ignores enemy_scene/formation/path motion and spawns
## `count` single instances of this scene (they fly on their own) at the
## path's start point (mirrored like a formation).
@export var scene_override: PackedScene
## Spawn this group at most once per zone visit: once something from it has
## spawned, later loops of the zone's waves skip the group (a capped spawn
## that produced nothing does not count, so it is retried next loop).
@export var one_shot: bool = false

# Short label for logs / debugging
func describe() -> String:
	var scene: PackedScene = scene_override if scene_override else enemy_scene
	var scene_name := scene.resource_path.get_file().get_basename() if scene else "?"
	return "%dx %s %s" % [count, scene_name, String(path)]
