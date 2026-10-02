# Art swap tracker

**Conventions.** Full-size art sources live in `art_archive/masters/` (Godot ignores
`art_archive/`); the game uses downscaled copies in `sprites/`: enemies and pickups 512 px
tall (the shield sphere 512 px plus a 12% transparent margin for its glow: 634x634), animated
pickup icons as horizontal sheets of 256x256 cells (frame-to-frame anchor fixed in the
cell center, >= 6 px transparent padding per cell; the `sheet` entries in the tool; the
asteroid sheets the same way, the small shards in 128 px cells on a 6x3 grid), the
UFO, the blimp and the docking station 1024 px wide, missiles 512 px along their length
turned nose-up (`rotate` in the tool; the missile scenes treat -y as forward), the ships at
their 1024x1536 canvas (not downscaled). Regenerate the copies with `tools/resize_art.gd` (see BUILD.md, "Art
pipeline") and re-fit the sprite scale as `old scale x old size / new size`. Downscaled
enemy and pickup textures import with mipmaps (`mipmaps/generate=true`) and their sprites
use `texture_filter = 4` (linear with mipmaps), otherwise the mipmaps are never sampled.
Enemy art is rim-lit and brightened per zone by the enemy shader on the dark skies
(upper atmosphere, space, orbit; see WAVE_DESIGN.md, "Enemy readability"), so enemy art
does not need its own light outline or glow to read on a dark background; keep the art's
own (dark) outline.

**Shield look.** The player's shield sphere in the `Sprite` style (`ShieldRing/Dome`) is
drawn through `shaders/shield_bubble.gdshader` (the pickup icon no longer uses it: it is
the animated `shield_icon` sheet, whose art carries its own glow); its look is tuned per instance with the ShaderMaterial
uniforms, no art change needed: `interior_strength` (hex pattern opacity inside the sphere;
player 0.55), `rim_color` / `rim_glow` (edge ring and halo), `glow_width` (halo
width into the margin; player 0.09), `rim_inner` / `rim_outer` /
`sphere_center` (where the sphere's edge sits in the texture: 0.355 / 0.378 /
(0.498, 0.494); re-measure them if the shield art or its padding changes).

**Shield style switch.** `GameConfig.shield_style` (`data/game_config.tres`, Pickups group;
main_level.gd hands it to `player.set_shield_style()`) picks the look of the player's
active shield: `Sprite` = `ShieldRing/Dome` above; `Procedural` (default) =
`ShieldRing/Field`, a 324x324 `ColorRect` (mouse ignored) at (-162, -168), centered on
the Dome's (0, -6), drawn only by `shaders/shield_procedural.gdshader` (no texture). Both
sit under `ShieldRing`, so the pulse, hit pop, last-2 s blink and end/death/landing hides
apply to either. The shield pickup icon is its own animated sheet (see the tracker row). Procedural uniforms
(shader defaults; `p = (UV - 0.5) * 2`, quad edge at 1): `edge_radius` 0.78 (= the
126 local px sphere), `aa` 0.01; `fill_color` (0.15, 0.5, 1) / `fill_alpha` 0.14;
`rim_color` (0.2, 0.62, 1) / `rim_glow` 1.1 / `rim_power` 2.5 (fresnel rim, also the halo
color); `edge_color` (0.85, 0.97, 1) / `edge_width` 0.035 / `edge_strength` 0.9 (thin
bright edge line); `highlight_strength` 0.25 (upper-left spot); `halo_width` 0.18 /
`halo_strength` 0.7 (keep `edge_radius + halo_width` <= 1); `hex_color` (0.4, 0.85, 1) /
`hex_scale` 2.6 / `hex_line_width` 0.03 / `hex_strength` 0.45 / `hex_drift` (0.03, -0.06);
`shimmer_speed` 0.6 / `shimmer_strength` 0.6; hit ripple `ripple_duration` 0.5 (keep equal
to `SHIELD_RIPPLE_DURATION` in player.gd) / `ripple_speed` 3.2 / `ripple_width` 0.15 /
`ripple_strength` 1.5. `hit_pos` / `hit_time` are set by player.gd when a hit is absorbed
(ripple from the shot / obstacle position, clamped onto the sphere; from the top if
unknown).
While shielded the hit area is the shield circle (radius 126 local, ~101 px on screen):
`CollisionArea/ShieldShape` at (0, -6), `player.gd` `shield_hit_radius`; keep it equal to
the drawn sphere edge if the shield art or `edge_radius` changes.

**Beam look.** The UFO tractor beam is procedural (no texture): `Beam/Field` in
`scenes/obstacles/ufo_obstacle.tscn`, a 200x520 `ColorRect` (mouse ignored) at (-100, 30),
drawn behind the hull by `shaders/ufo_beam.gdshader` (per-instance ShaderMaterial,
`resource_local_to_scene`). UV (0.5, 0) is the saucer's emitter, v runs down the beam.
Uniforms (shader defaults): cone `top_half_width` 0.2 / `bottom_half_width` 0.4 (fractions
of the quad width: 80 px wide at the emitter, ~160 px at the end of the BeamArea polygon,
y 530) / `edge_softness` 0.45 (sides half faded at the nominal width, gone at
1 + 0.5 x softness; keep `bottom_half_width * (1 + 0.5 * edge_softness)` < 0.5);
`fade_power` 0.9 / `end_fade` 0.15 (last 15% fades to 0, by y 550) / `emitter_glow` 0.8;
`beam_color` (0.85, 0.35, 1) / `core_color` (1, 0.85, 0.97) / `beam_alpha` 0.35 /
`core_strength` 0.6; rings scrolling up toward the saucer `ring_count` 6 / `ring_speed` 0.9
/ `ring_width` 0.14 / `ring_strength` 0.55 / `ring_curve` 0.35; `shimmer_strength` 0.3
(sideways wobble + two drifting bands); `capture` 0..1 (set by code). `ufo_obstacle.gd`
drives `Beam.modulate.a` (fade in/out over `beam_fade_time` 0.3 s times a pulse between
`beam_alpha_min` 0.8 and `beam_alpha_max` 1.0) and `capture` (toward 1 while the player
is in the beam, back to 0 otherwise, over `capture_time` 0.2 s: brighter core and rings
plus a second, faster ring set). Bolt uniforms (set by code, see WAVE_DESIGN.md "UFO
weapons and scout saucers"): `charge` 0..1 (the bolt charge while the player stays in the
beam: the core narrows and heats toward `charge_color` (white), the rings brighten up to
2.2x, and `charge_bands` (3) bright bands sweep down the beam as the charge rises; their
position follows the charge itself, so they never jump), `bolt` 1 -> 0 over 0.15 s when the
bolt fires (the whole cone flashes white, brightest in a narrow center column; the code
lifts `Beam.modulate.a` to at least `bolt` so the pulse can't dim it). Both sit behind
uniform branches (no cost while idle). If the cone changes, keep `Beam/BeamArea`'s polygon
(-40, 30) (40, 30) (80, 530) (-80, 530) matching it.

**Coin look.** The energy coin is procedural (no texture): `Sprite2D/Coin` in
`scenes/collectibles/energy_collectible_1.tscn`, a 56x56 `ColorRect` (mouse ignored) at
(-28, -28) under an untextured Sprite2D (GameObject's `sprite`, hidden on collect), drawn
by `shaders/coin.gdshader` (per-instance ShaderMaterial, `resource_local_to_scene`). The
old pixel sprite `sprites/pixil-frame-0(1).png` is no longer used. A short gold cylinder
turned about the vertical axis: face ellipse plus edge band (still ~8 px wide edge-on,
never vanishes), back face tinted, embossed rim and emblem, light that changes with the
spin (flat face light capped so a fully lit face stays gold), a darker groove tracing the
emblem and the rim's inner edge (drawn after the glint, so the emblem reads at every open
phase), a narrow glint band sweeping the front face once per turn, a thin dark outline, a
soft warm glow and a short twinkle on the upper-left edge of the face (skipped while
edge-on). ~34 px across face-on (the old coin was 31 px); collision circle r 16 unchanged.
`energy_collectible.gd` sets `spin_angle` (0..TAU) and `twinkle_phase` (0..1) every frame
from `time_alive` (pause-safe), with a random spin phase and speed and a random twinkle
offset rolled on every spawn (`coin_spin_speed` 4.5 rad/s, `coin_spin_speed_variation`
0.15, `coin_twinkle_period` 3.6 s, about one twinkle every 2.6 turns); the old `scale.x`
flip is skipped for it. The collect pop (`scripts/effects/coin_pop.gd`) flashes an
additive white-gold core that collapses over the first 30% of the pop, then a ring and
sparks; the gold "+5" starts 26 px above the coin (`main_level.gd`
`COIN_POPUP_OFFSET`), clear of the flash.
Uniforms worth tuning (shader defaults): `emblem` 1 = five-point star (default, chosen
from the emblem renders), 0 = microchip, 2 = lightning bolt (the shader default is the
source of truth; the scene's ShaderMaterial stores no emblem, and setting one there
applies to every coin); `radius_px` 16 / `quad_px` 56 (keep `quad_px` equal to the ColorRect size and
`radius_px + outline_px + glow_px` under `quad_px / 2`); `thickness` 0.24 (edge width in
face radii); `rim_inner` 0.74 / `rim_outer` 0.9; `gold_dark` / `gold_mid` / `gold_light`
(the gold ramp), `face_lum_max` 0.62 (brightest flat face value; higher turns a lit face
cream and washes the emblem out), `edge_tint`, `back_tint`; `emboss_strength` 0.9;
`groove_px` 1.0 / `groove_strength` 0.42 (emblem and rim groove, pulled toward
`gold_dark`); `light_dir` (-0.45, -0.55, 0.7); `glint_strength` 0.45 / `glint_width` 0.09;
`outline_color` / `outline_px` 1.25; `glow_color` / `glow_strength` 0.35 / `glow_px` 7
(keep the glow subtle: it sits on the light ground sky too); `twinkle_strength` 1.6 /
`twinkle_len` 0.08 (fraction of the twinkle cycle, ~0.29 s) / `twinkle_px` 10 /
`twinkle_pos` (-0.62, -0.66) (face radii, on the rim).

Every placeholder in the code carries a `PLACEHOLDER_ART:` comment at the exact line to
change. `grep -rn PLACEHOLDER_ART scripts scenes data` lists what is still standing in.
This table is the human-readable view; keep both in sync when adding or swapping art.

Status values: `placeholder` (code ready, stand-in art), `art ready` (file delivered,
not yet wired), `swapped` (final art in place, marker removed).

| Feature | Where to swap | Current stand-in | Art needed | Status |
|---|---|---|---|---|
| (rows are appended by each implementation phase) | | | | |
| Ship: TI SoM - AM62Px (balanced) | `data/ships/phycore_am62x.tres` → `texture` (id `ti_am62px`, tint white) | — | `sprites/player_ship_body1.png` (1024x1536, drawn at the Player's Ship scale 0.125 = 128x192 px; the art fills the canvas, ~127x169 px visible vs ~112x140 for body2). Reference size for all ships: `visual_scale` 1.0, `visual_offset_y` 0, visible y -95.1..73.5 local (~135 px tall on screen at the Player's 0.8); hardpoints nose -89, wing guns (±38, -20), engines 67, side thrusters 22 | swapped |
| Ship: i.MX SoM - i.MX95 (heavy) | `data/ships/phycore_imx8mp.tres` → `texture` (id `nxp_imx95`, tint white) | — | `sprites/player_ship_body3.png` (1024x1536 at 0.125, ~126x186 px visible unscaled) drawn at `visual_scale` 0.909, `visual_offset_y` -8.88: ~115x169 local px visible, same top/bottom (y -95.1..73.5) as the AM62Px; hardpoints nose -89, wing guns (±34.5, -44.3), engines 68.4, side thrusters 14.8 | swapped |
| Ship: Qualcomm SoM - IQ2390 (light) | `data/ships/phycore_imx93.tres` → `texture` (id `qualcomm_iq2390`, tint white) | — | `sprites/player_ship_body4.png` (1024x1536 at 0.125, ~127x181 px visible unscaled) drawn at `visual_scale` 0.9349, `visual_offset_y` -5.96: ~119x169 local px visible, same top/bottom (y -95.1..73.5) as the AM62Px; hardpoints nose -89, wing guns (±35.5, -20.0), engines 67.9, side thrusters 18.3 | swapped |
| Drone swarm enemy | `scenes/obstacles/drone_obstacle.tscn` Sprite2D `texture` / `scale` + CircleShape2D (note in `scripts/obstacles/drone_obstacle.gd`) | — | `sprites/drone_1.png` (512x512, master 1254x1254) at Sprite2D scale 0.0784, ~40 px on screen, collision circle r 15 at (0, -2); static (optional later: 2-4 frame rotor loop as hframes) | swapped |
| Blimp mini-boss | `scenes/obstacles/blimp_obstacle.tscn` Sprite2D `texture` / `rotation` / `scale` + CapsuleShape2D + GunPoint1-3 (note in `scripts/obstacles/blimp_obstacle.gd`) | — | `sprites/zeppelin_1.png` (1024x393, the zeppelin cut from master `zeppelin_weapon_combined.png`; top-down, nose drawn to the right) on a Sprite2D rotated 90 deg (nose down) at scale 0.24, ~94x246 px visible (1.33x the first fit, so a ship centered under it lands all three tier-2 shots), untinted; capsule r 40 / height 229 at (0, 5); GunPoint1/3 on the forward side pods (x -+41, y 28), GunPoint2 on the gondola cockpit (0, 40). Unused so far: the sheet's six weapon modules; optional later: propeller loop, damaged variant | swapped |
| UFO saucer | `scenes/obstacles/ufo_obstacle.tscn` Sprite2D `texture` / `scale` + hull CapsuleShape2D (note in `scripts/obstacles/ufo_obstacle.gd`) | — | `sprites/ufo_1.png` (1024x512, master 1774x887; revised art with a hex-pattern dome, first version kept in `art_archive/art_old/ufo_1_v1.png`) at Sprite2D scale 0.2079, ~213x106 canvas (~210x84 px visible), level, untinted; hull capsule 200x52 at y+6; emitter glow centered at y ~38 (beam starts behind the hull at y 30, unchanged) | swapped |
| UFO tractor beam | `scenes/obstacles/ufo_obstacle.tscn` `Beam/Field` ColorRect + `shaders/ufo_beam.gdshader` (note in `scripts/obstacles/ufo_obstacle.gd`; see "Beam look") | — | Procedural shader, no texture: soft magenta-violet cone from the emitter (y 30, 80 px wide, behind the hull) to ~160 px wide at y 530, bright core and emitter glow, curved rings scrolling up toward the saucer, fading out by y 550; fades in/out over 0.3 s, brightens with faster rings while the player is caught (`capture`); heats to white with bands sweeping down while the bolt charges (`charge`) and flashes white when it fires (`bolt`). `Beam/BeamArea` polygon unchanged | code-only (shader) |
| UFO pulse-ring tell | `scripts/obstacles/ufo_obstacle.gd` `_set_ring_telegraph()` (sprite `self_modulate` toward `ring_telegraph_color` (1.9, 1.6, 2.2), two pulses over the 0.4 s tell) | Whole saucer sprite flares bright (hull near white, lights hot purple) | None (code-only); optionally a 2-3 frame "lights charging" overlay for the rim lights | code-only |
| Scout saucer (second-colour UFO, `ufo_2`) | `scenes/obstacles/scout_ufo_obstacle.tscn` Sprite2D `texture` / `scale` + CapsuleShape2D + GunPoint1 (note in `scripts/obstacles/scout_ufo_obstacle.gd`) | — | `sprites/ufo_2.png` (1024x512, master 1774x887: the mini-boss saucer's silhouette with teal lights) at Sprite2D scale 0.1247 (60% of the mini-boss), ~127x64 canvas (~127x51 px visible), untinted, root `hue_shift` 0 (the hit flash shader's hue rotation that stood in for it is unused now). Visible bounds (alpha >= 128) 1761x715 master px vs `ufo_1`'s 1747x698 (+0.8% wide, +2.4% tall: 126.8 vs 125.7 px wide, 51.5 vs 50.2 px tall on screen; center within 0.2 px), so scale, capsule (r 16 / h 120 at y+4) and GunPoint1 (0, 22) are unchanged | swapped |
| Splitting asteroid | `scenes/obstacles/asteroid_obstacle.tscn` `AnimatedSprite2D` `sprite_frames` / `scale` + `size_animations` / `size_sprite_scales` / `large_tumble_fps` in `scripts/obstacles/asteroid_obstacle.gd` (note in its header) | `sprites/meteor_1.png`, same texture for all three sizes (scaled 1.6/1.0/0.6) | One `AnimatedSprite2D` with `sprites/asteroid.tres`, one or more animations per size (`size_animations`, one picked per spawn). Large: two rocks, `large_1` (`sprites/asteroid_large_sheet.png`, master `meteor_animated_large_1.png`) and `large_2` (`sprites/asteroid_large_sheet_2.png`, master `asteroid_large_sheet_2.png`), each an 8-frame tumble (2048x256: 8 cells of 256x256, repacked from a 1774x887 4x2 master, 544 master px per cell, centered on the rock's alpha centroid so it does not jitter), 50/50 per spawn, looping at `large_tumble_fps` 6 from a random frame, forward or backward (0 = each rock holds one random frame: 16 looks). Medium: `medium`, 8 different chunks held (`sprites/asteroid_chunks_sheet.png`, 2048x256, master `meteor_medium_chunks.png`, 544 px per cell). Small: `small`, 18 different shards held (`sprites/asteroid_shards_sheet.png`, 768x384: 6x3 cells of 128x128, master `meteor_small_shards_various_1.png`, 416 px per cell). Chunks and shards are cut out as alpha islands (the `grid` sheet mode in the tool) and centered on their bounding box. Split siblings get different frames; the code spin applies to every size. Node scale still carries `size_scales` 1.6/1.0/0.6 (collision r 20 scales with it); sprite scale per size 0.252 / 0.252 / 0.545 brings the mean longest visible side to ~80 / 50 / 30 px (per-frame range 77-84, 46-55, 28-34 px; the art's own size spread is kept). Enemy shader rim and brighten as for the other enemies. Health, damage, points and collision unchanged. Sheets imported with mipmaps | swapped |
| Space mine | `scenes/obstacles/mine_obstacle.tscn` Sprite2D `texture` / `scale` + CircleShape2D; light pulse in `scripts/obstacles/mine_obstacle.gd` `_set_light()` (sprite `modulate` toward `idle_light_color` / `armed_light_color`) | — | `sprites/mine_1.png` (512x512, master 1254x1254) at Sprite2D scale 0.103, ~53 px on screen incl. spikes, collision circle r 16 (body only) | swapped |
| Docking station (victory) | `scenes/effects/docking_station.tscn` Sprite2D `Hull` `texture` / `scale` + `DockPoint`; `PAD_RECT` / `landing_scale` in `scripts/effects/docking_station.gd` | — | `sprites/space_station_1.png` (1024x341, master 2172x724; top-down, solar/cargo modules left and right, central landing pad with an orange crosshair) on `Hull` at scale 0.6641 = 680x226 px on screen, `texture_filter = 4`; resting at y 260 (on screen y 147..373). Pad (dark rectangle, texture px 404..621 x 111..231) = station-local rect (-71.7, -39.5) 144x80, on screen x 288..432, y 220..300; `DockPoint` (0, 1) on the crosshair. The ship lands on the pad: `fly_to` shrinks it from 0.8 to `landing_scale` 0.36 (every ship ~46x61 px after `visual_scale`, inside the pad). Optional later: animated pad lights (2-4 frames) | swapped |
| Docking touchdown (victory) | `scripts/effects/docking_station.gd` `_on_touchdown()` (`TouchdownRing` Line2D) | Clamps dropped: the station art has a landing pad, so the ship lands instead of docking into a port. Touchdown = green Line2D ring growing from the crosshair (r 10 → 90 px) and fading out over 0.4 s, under the ship | None (code-only); optional later: animated pad lights, 2-4 frames, as a Sprite2D with hframes over the pad | code-only |
| Docking flash + "DOCKED" label | `scripts/effects/docking_station.gd` (`DockFlash`, `DockedLabel`) | White Polygon2D flash over the landing pad (0.2 s), gold m5x7 "DOCKED" label pop under the station | None (code-only effect) | code-only |
| Score / graze popups, combo HUD, screen shake | `scenes/effects/juice_score_popup.tscn`, `scenes/ui/game_hud_ui.tscn` `ComboBox`, `scripts/effects/juice_camera_shake.gd` | m5x7 text with outline, ProgressBar, camera offset | None (code-only effects) | code-only |
| Spawn telegraph marker | `scenes/effects/spawn_telegraph.tscn` `Chevron` Polygon2D + `Label` (marker in `scripts/effects/spawn_telegraph.gd`) | Yellow Polygon2D chevron (60x40 px, rotated toward the entry direction) plus a yellow "!" Label with black outline, blinked in code | 96x96 transparent PNG sheet, 2-3 frames (e.g. pulse / arrow bob), yellow warning chevron + "!" pointing down (code rotates it toward the entry heading); replace both nodes with an AnimatedSprite2D or a Sprite2D with hframes | placeholder |
| Health cell pickup | `scenes/collectibles/health_pickup.tscn` `AnimatedSprite2D` `sprite_frames` / `scale` (note in `scripts/collectibles/health_pickup.gd`) | Polygon2D dark rounded square (56 px) with a green Line2D border and a green Polygon2D cross | `sprites/health_pickup_sheet.png` (1280x256: 5 cells of 256x256, each centered on the red cross; repacked from the 2172x724 master `health_pickup_sprite_sheet.png`, 576 master px per cell) via `sprites/health_pickup.tres`, looping 0-1-2-3-4 at 8 fps; the canister "breathes" (1.27x wider in frame 2, intended, not normalized). Scale 0.3675 (25% smaller than the first 0.49 pass, user request): canister ~42 px wide in frames 0/4, ~54 px in frame 2, sparkles/base up to ~75x84 px. No spin (`spin = false`); collision circle shrunk with the art, r 28 -> 21 (42 px, the smallest canister width). Sheet imported with mipmaps like the shield sheet | swapped |
| Shield bubble pickup | `scenes/collectibles/shield_pickup.tscn` `AnimatedSprite2D` `sprite_frames` / `scale` (note in `scripts/collectibles/shield_pickup.gd`) | — | `sprites/shield_icon_sheet.png` (1280x256: 5 cells of 256x256, the hex sphere centered and the same size in every cell, rim radius ~90 px; repacked from the 2172x724 glow-pulse master `shield_icon_sprite_sheet.png`, 512 master px per cell) via `sprites/shield_icon.tres`, looping 0-1-2-3-4 at 8 fps; scale 0.3 = ~55 px sphere on screen (glow up to ~72 px). No shader material (the art has its own glow), no spin (`spin = false`); collision circle r 28 unchanged | swapped |
| Screen-clear bomb pickup | `scenes/collectibles/bomb_pickup.tscn` `AnimatedSprite2D` `sprite_frames` / `scale` (note in `scripts/collectibles/bomb_pickup.gd`) | — | `sprites/bomb_pickup_sheet.png` (1536x256: 6 cells of 256x256, each centered on the round body; repacked from the 2172x724 master `bomb_collectible_2.png`, 560 master px per cell, alpha < 5 haze dropped, min padding 7 px) via `sprites/bomb_pickup.tres`, looping 0-5 at 8 fps: the core heats up, steam vents (frame 3 drawn 1.12x larger, intended, not normalized), settles. Scale 0.393: body ~50 px on screen in the resting frames 0/5 (~56 px in frame 3; fuse flame and steam reach further). No spin (`spin = false`); collision circle r 28 -> 25 (the body). Sheet imported with mipmaps like the shield / health sheets. The previous static icon is archived: `art_archive/art_old/bomb_collectible_1.png` (game copy, 560x512) and `bomb_collectible_1_master.png` (1312x1199) | swapped |
| Player shield ring | `scenes/player.tscn` `ShieldRing/Dome` Sprite2D (note in `scripts/main_level/player.gd`); code drives ShieldRing's scale / modulate / visibility (pulse, hit pop, last-2 s blink) | — | `sprites/shield_dome_1.png` (634x634 full sphere, master 1254x1254) at scale 0.5258, position (0, -6) (within 5 local px of the ships' common visible center, y -10.8): sphere radius 126 local px, ~17 px outside the farthest corner of the ships' visible bounding box (~10 px at the -5% pulse); ~204 px sphere on screen at the Player's 0.8, halo to ~251 px. `shield_bubble.gdshader` with `interior_strength` 0.55 (faded hex pattern), cyan-white rim ring + halo (see "Shield look"). Old half-dome art kept in `art_archive/art_old/shield_dome_half.png` | swapped |
| Bomb screen flash, shield HUD indicator | `scripts/main_level.gd` `_start_bomb_flash()` (white ColorRect under `UI`, 0.25 s), `scenes/ui/game_hud_ui.tscn` `ShieldBox` | ColorRect fade, m5x7 "SHIELD" label + ProgressBar | None (code-only effects) | code-only |
| Enemy hit flash + scale punch | `shaders/hit_flash.gdshader` (assigned per instance in `scripts/obstacles/obstacle.gd` `_setup_hit_flash()`; driven by `_on_hit()` / `_update_hit_feedback()`) | White mix on the sprite (0.08 s) and a 1.12x scale punch (0.1 s) | None (code-only effect; works with any swapped enemy texture) | code-only |
| Enemy hit sparks | `scenes/effects/hit_spark.tscn` CPUParticles2D (marker in `scripts/effects/hit_spark.gd`) | 7 untextured white -> yellow squares, 0.25 s one-shot burst | 2-3 frame spark sheet, ~64x64 per frame, transparent PNG, white/yellow star; set as the particles `texture` with a CanvasItemMaterial using `particles_animation` (like `obstacle_explosion.tscn`) | placeholder |
| Enemy mini health bar | `scenes/effects/enemy_health_bar.tscn` `Back` / `Fill` ColorRects (marker in `scripts/effects/enemy_health_bar.gd`) | Dark 40x5 ColorRect back + red -> yellow ColorRect fill | None (code-only); optionally a 40x5 frame + fill texture (TextureProgressBar) | code-only |
| Enemy hit sound | `scripts/obstacles/obstacle.gd` `hit_sound` export (marker there; per-scene overrides possible) | `audio/retro-coin-1.mp3` at pitch 2.4, -16 dB, max one per 50 ms | Short hit tick, 0.1-0.2 s, mp3/ogg (dry, high, non-tonal so rapid repeats don't read as coins); reset `hit_sound_pitch` to 1.0 | placeholder |
| Player missile (missile upgrade) | `scenes/effects/player_missile.tscn` `Sprite2D` + `Trail` CPUParticles2D (note in `scripts/effects/player_missile.gd`) | — | `sprites/side_winder_missile_2.png` (172x512, blue/white livery with cyan lights, from the 2172x724 master `side_winder_missile_2.png` drawn nose-right: cropped to the art (alpha >= 5: x 60..2122, y 12..691) + 16 px along / 12 px across, turned nose-up by `tools/resize_art.gd` `rotate` 90, 512 px along its length) on a Sprite2D at scale 0.0918, `texture_filter = 4`: ~46x15 px on screen (fins; body ~7 px), nose up = -y, which the code turns along the velocity. Its visible length in the game copy (504 px) matches the red `side_winder_missile_1` within 0.1% (the masters differ 4%, the crop margin evens it out), so scale, trail origin (0, 22) and collision capsule (r 6 / h 44) are unchanged. The red/white livery is the zeppelin's. Optional later: a 3-frame exhaust flame (AnimatedSprite2D at the nozzle) or a flame texture for the trail particles | swapped |
| Missile upgrade pickup | `scenes/collectibles/missile_pickup.tscn` `Sprite2D` (untextured parent, pulsed by the code) with `Tile` / `Border` / `Missile` children (note in `scripts/collectibles/missile_pickup.gd`) | — | Tile and border stay code-drawn by design (user's choice): dark rounded 48x48 Polygon2D tile, 3 px orange Line2D border, unchanged. `Missile` = a Sprite2D of the player's blue/white `sprites/side_winder_missile_2.png` at scale 0.087 (~44x15 px), rotated 45 deg (nose up-right), at (1.75, -1.75) (2.5 px toward the nose; 3.76 px between any opaque pixel and the border's inner edge, >= the 3.5 px rule, so the fit of the red art carries over), `self_modulate` (1.2, 1.2, 1.2) (brighter in the icon only; picked from 1.0 / 1.2 / 1.35 / 1.5 on the atmosphere and space skies: 1.0 reads grey on the dark tile, 1.35 starts to flatten the white collars, 1.5 blows the white body out), `texture_filter = 4`. Collision circle r 26 | swapped |
| Zeppelin missile (enemy) | `scenes/effects/enemy_missile.tscn` `Sprite2D` `texture` + `Trail` CPUParticles2D (note in `scripts/effects/enemy_missile.gd`) | — | `sprites/side_winder_missile_1.png` (178x512, the red/white livery; the player's missiles use the blue/white `side_winder_missile_2`) untinted (the rust-orange `self_modulate` stand-in removed), scale 0.1 = ~50x17 px, nose up = -y (turned along the velocity, so it flies nose-down at the player); smoke trail from the nozzle (0, 24); collision capsule r 6 / h 48. The root's `modulate` stays free for the hit flash | swapped |
| Zeppelin missile launch flash | `scenes/obstacles/blimp_obstacle.tscn` `PodFlashLeft` / `PodFlashRight` Polygon2D stars (driven by `_set_pod_flash()` in `scripts/obstacles/blimp_obstacle.gd`) | Orange 16-px 8-point star with a pale core at each side pod, scaled 0.6 -> 1.4 and flickering over the 0.35 s telegraph | None (code-only effect); optionally a 2-3 frame muzzle-glow sheet | code-only |
| Seeker orb (Alien Mothership) | `scenes/effects/alien_seeker.tscn` `Glow` ColorRect + `shaders/alien_seeker.gdshader` (notes in `scripts/effects/alien_seeker.gd`) | — | Procedural shader, no texture: 64x64 quad (mouse ignored) at (-32, -32), `p = (UV - 0.5) * 2`. Uniforms (defaults): `halo_color` (0.95, 0.2, 0.85) / `halo_strength` 0.8 (soft glow to the quad edge); `shell_radius` 0.5 / `shell_width` 0.12 / `shell_color` (1, 0.45, 0.95) (the ring, ~32 px across on screen); `core_color` (0.45, 1, 0.35) / `core_radius` 0.34 / `pulse_speed` 7 / `pulse_amount` 0.2 (pulsing alien-green core, white-hot center). COLOR (modulate) multiplies last: `alien_seeker.gd` drives the hit flash and the last-1 s fast-blink tell (modulate 2.2x / 0.35 alpha at 14 toggles/s). Collision circle r 14 | code-only (shader) |
| Missiles HUD indicator, missile pop / burst flashes | `scenes/ui/game_hud_ui.tscn` `HeightContainer/MissileBox`; pops and the orb burst reuse `scenes/effects/explosion.tscn` (SMALL / ENERGY) | m5x7 orange "MISSILES" label + ProgressBar | None (code-only effects) | code-only |
