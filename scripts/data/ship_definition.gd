# ship_definition.gd
# One selectable player ship ("SoM"). Listed in GameConfig.ships; the chosen
# one is held by the GameSession autoload and applied by player.gd /
# main_level.gd when a run starts.
class_name ShipDefinition
extends Resource

## Stable id (identifies the ship; not persisted anywhere).
@export var id: StringName = &""
## Name shown on the ship select screen and in the HUD.
@export var display_name: String = ""
## One-line summary shown under the name (e.g. "Balanced all-rounder").
@export var tagline: String = ""
## Short extra text for the ship select screen.
@export_multiline var description: String = ""
## Ship body sprite (1024x1536, facing up, engine at bottom center; drawn at
## the Player's Ship sprite scale 0.125, i.e. 128x192 px on screen).
@export var texture: Texture2D
## Modulate applied to the ship sprite (white = untinted).
@export var tint: Color = Color(1, 1, 1)
@export_group("Stats")
## Player health at the start of a run (HUD shows it as a percentage).
@export var max_health: float = 100.0
## Movement speed (px/s).
@export var speed: float = 300.0
## Multiplies every weapon tier's fire cooldown (< 1 = fires faster).
@export var fire_cooldown_scale: float = 1.0
## Multiplies player projectile damage.
@export var damage_scale: float = 1.0

## Shots per second relative to the default ship (for UI stat bars).
func get_fire_rate_factor() -> float:
	return 1.0 / maxf(fire_cooldown_scale, 0.01)
