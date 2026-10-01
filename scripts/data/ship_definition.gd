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
## Uniform factor on the Ship sprite's base scale 0.125 (player.gd
## apply_ship(); the ship select preview and cards apply it too). The three
## ship textures fill their canvas differently; this makes every ship show
## the first ship's visible height (TI AM62Px: ~168.6 local px, ~135 px on
## screen at the Player's 0.8). 1 = unscaled.
@export var visual_scale: float = 1.0
## Ship sprite y offset (Player-local px), applied after visual_scale so the
## visible art's center sits at the first ship's (y -10.8): the shield at
## (0, -6), the nose and the tail line up on every ship.
@export var visual_offset_y: float = 0.0
@export_group("Stats")
## Player health at the start of a run (HUD shows it as a percentage).
@export var max_health: float = 100.0
## Movement speed (px/s).
@export var speed: float = 300.0
## Multiplies every weapon tier's fire cooldown (< 1 = fires faster).
@export var fire_cooldown_scale: float = 1.0
## Multiplies player projectile damage.
@export var damage_scale: float = 1.0
@export_group("Hardpoints")
# Positions in the Player's local space (on-screen px at the Ship sprite scale
# 0.125, ship center = origin, nose up), measured on the art as drawn, i.e.
# after visual_scale / visual_offset_y. Applied by player.gd apply_ship();
# defaults are the Player scene's original values (sized for body2).
## Center gunpoint y (a few px inside the visible nose tip).
@export var nose_offset_y: float = -73.0
## Left/right gunpoint |x| (tier 2+ side guns; mirrored).
@export var wing_gun_x: float = 28.0
## Left/right gunpoint y.
@export var wing_gun_y: float = -1.0
## MainThruster / MainThruster2 y (a few px inside the engine row).
@export var engine_offset_y: float = 48.0
## LeftThruster / RightThruster y (Up/Down thrusters are not moved).
@export var side_thruster_y: float = 22.0

## Shots per second relative to the default ship (for UI stat bars).
func get_fire_rate_factor() -> float:
	return 1.0 / maxf(fire_cooldown_scale, 0.01)
