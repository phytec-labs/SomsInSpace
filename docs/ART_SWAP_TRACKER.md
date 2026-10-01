# Art swap tracker

**Conventions.** Full-size art sources live in `art_archive/masters/` (Godot ignores
`art_archive/`); the game uses downscaled copies in `sprites/`: enemies and pickups 512 px
tall (the shield sphere 512 px plus a 12% transparent margin for its glow: 634x634), animated
pickup icons as horizontal sheets of 256x256 cells (frame-to-frame anchor fixed in the
cell center, >= 6 px transparent padding per cell; the `sheet` entries in the tool), the
UFO, the blimp and the docking station 1024 px wide, the ships at their 1024x1536 canvas
(not downscaled). Regenerate the copies with `tools/resize_art.gd` (see BUILD.md, "Art
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
plus a second, faster ring set). If the cone changes, keep `Beam/BeamArea`'s polygon
(-40, 30) (40, 30) (80, 530) (-80, 530) matching it.

Every placeholder in the code carries a `PLACEHOLDER_ART:` comment at the exact line to
change. `grep -rn PLACEHOLDER_ART scripts scenes data` lists what is still standing in.
This table is the human-readable view; keep both in sync when adding or swapping art.

Status values: `placeholder` (code ready, stand-in art), `art ready` (file delivered,
not yet wired), `swapped` (final art in place, marker removed).

| Feature | Where to swap | Current stand-in | Art needed | Status |
|---|---|---|---|---|
| (rows are appended by each implementation phase) | | | | |
| Ship: TI SoM - AM62Px (balanced) | `data/ships/phycore_am62x.tres` → `texture` (id `ti_am62px`, tint white) | — | `sprites/player_ship_body1.png` (1024x1536, drawn at the Player's Ship scale 0.125 = 128x192 px; the art fills the canvas, ~127x169 px visible vs ~112x140 for body2) | swapped |
| Ship: i.MX SoM - i.MX95 (heavy) | `data/ships/phycore_imx8mp.tres` → `texture` (id `nxp_imx95`, tint white) | — | `sprites/player_ship_body3.png` (1024x1536 at 0.125, ~126x186 px visible) | swapped |
| Ship: Qualcomm SoM - IQ2390 (light) | `data/ships/phycore_imx93.tres` → `texture` (id `qualcomm_iq2390`, tint white) | — | `sprites/player_ship_body4.png` (1024x1536 at 0.125, ~127x181 px visible) | swapped |
| Drone swarm enemy | `scenes/obstacles/drone_obstacle.tscn` Sprite2D `texture` / `scale` + CircleShape2D (note in `scripts/obstacles/drone_obstacle.gd`) | — | `sprites/drone_1.png` (512x512, master 1254x1254) at Sprite2D scale 0.0784, ~40 px on screen, collision circle r 15 at (0, -2); static (optional later: 2-4 frame rotor loop as hframes) | swapped |
| Blimp mini-boss | `scenes/obstacles/blimp_obstacle.tscn` Sprite2D `texture` / `rotation` / `scale` + CapsuleShape2D + GunPoint1-3 (note in `scripts/obstacles/blimp_obstacle.gd`) | — | `sprites/zeppelin_1.png` (1024x393, the zeppelin cut from master `zeppelin_weapon_combined.png`; top-down, nose drawn to the right) on a Sprite2D rotated 90 deg (nose down) at scale 0.24, ~94x246 px visible (1.33x the first fit, so a ship centered under it lands all three tier-2 shots), untinted; capsule r 40 / height 229 at (0, 5); GunPoint1/3 on the forward side pods (x -+41, y 28), GunPoint2 on the gondola cockpit (0, 40). Unused so far: the sheet's six weapon modules; optional later: propeller loop, damaged variant | swapped |
| UFO saucer | `scenes/obstacles/ufo_obstacle.tscn` Sprite2D `texture` / `scale` + hull CapsuleShape2D (note in `scripts/obstacles/ufo_obstacle.gd`) | — | `sprites/ufo_1.png` (1024x512, master 1774x887) at Sprite2D scale 0.2079, ~213x106 canvas (~210x81 px visible), level, untinted; hull capsule 200x52 at y+6 | swapped |
| UFO tractor beam | `scenes/obstacles/ufo_obstacle.tscn` `Beam/Field` ColorRect + `shaders/ufo_beam.gdshader` (note in `scripts/obstacles/ufo_obstacle.gd`; see "Beam look") | — | Procedural shader, no texture: soft magenta-violet cone from the emitter (y 30, 80 px wide, behind the hull) to ~160 px wide at y 530, bright core and emitter glow, curved rings scrolling up toward the saucer, fading out by y 550; fades in/out over 0.3 s, brightens with faster rings while the player is caught (`capture`). `Beam/BeamArea` polygon unchanged | code-only (shader) |
| Splitting asteroid | `scenes/obstacles/asteroid_obstacle.tscn` Sprite2D `texture` (marker in `scripts/obstacles/asteroid_obstacle.gd`) | `sprites/meteor_1.png`, same texture for all three sizes (scaled 1.6/1.0/0.6) | Rocky asteroid without flame trail, transparent PNG, roughly round, ~50 px at size 2 (author at 200x200); ideally 3 variants (large/medium/small or cracked stages) so pieces read as fragments; spins in code, so no rotation frames needed | placeholder |
| Space mine | `scenes/obstacles/mine_obstacle.tscn` Sprite2D `texture` / `scale` + CircleShape2D; light pulse in `scripts/obstacles/mine_obstacle.gd` `_set_light()` (sprite `modulate` toward `idle_light_color` / `armed_light_color`) | — | `sprites/mine_1.png` (512x512, master 1254x1254) at Sprite2D scale 0.103, ~53 px on screen incl. spikes, collision circle r 16 (body only) | swapped |
| Docking station (victory) | `scenes/effects/docking_station.tscn` Sprite2D `Hull` `texture` / `scale` + `DockPoint`; `PAD_RECT` / `landing_scale` in `scripts/effects/docking_station.gd` | — | `sprites/space_station_1.png` (1024x341, master 2172x724; top-down, solar/cargo modules left and right, central landing pad with an orange crosshair) on `Hull` at scale 0.6641 = 680x226 px on screen, `texture_filter = 4`; resting at y 260 (on screen y 147..373). Pad (dark rectangle, texture px 404..621 x 111..231) = station-local rect (-71.7, -39.5) 144x80, on screen x 288..432, y 220..300; `DockPoint` (0, 1) on the crosshair. The ship lands on the pad: `fly_to` shrinks it from 0.8 to `landing_scale` 0.36 (largest ship ~46x67 px, inside the pad). Optional later: animated pad lights (2-4 frames) | swapped |
| Docking touchdown (victory) | `scripts/effects/docking_station.gd` `_on_touchdown()` (`TouchdownRing` Line2D) | Clamps dropped: the station art has a landing pad, so the ship lands instead of docking into a port. Touchdown = green Line2D ring growing from the crosshair (r 10 → 90 px) and fading out over 0.4 s, under the ship | None (code-only); optional later: animated pad lights, 2-4 frames, as a Sprite2D with hframes over the pad | code-only |
| Docking flash + "DOCKED" label | `scripts/effects/docking_station.gd` (`DockFlash`, `DockedLabel`) | White Polygon2D flash over the landing pad (0.2 s), gold m5x7 "DOCKED" label pop under the station | None (code-only effect) | code-only |
| Score / graze popups, combo HUD, screen shake | `scenes/effects/juice_score_popup.tscn`, `scenes/ui/game_hud_ui.tscn` `ComboBox`, `scripts/effects/juice_camera_shake.gd` | m5x7 text with outline, ProgressBar, camera offset | None (code-only effects) | code-only |
| Spawn telegraph marker | `scenes/effects/spawn_telegraph.tscn` `Chevron` Polygon2D + `Label` (marker in `scripts/effects/spawn_telegraph.gd`) | Yellow Polygon2D chevron (60x40 px, rotated toward the entry direction) plus a yellow "!" Label with black outline, blinked in code | 96x96 transparent PNG sheet, 2-3 frames (e.g. pulse / arrow bob), yellow warning chevron + "!" pointing down (code rotates it toward the entry heading); replace both nodes with an AnimatedSprite2D or a Sprite2D with hframes | placeholder |
| Health cell pickup | `scenes/collectibles/health_pickup.tscn` `AnimatedSprite2D` `sprite_frames` / `scale` (note in `scripts/collectibles/health_pickup.gd`) | Polygon2D dark rounded square (56 px) with a green Line2D border and a green Polygon2D cross | `sprites/health_pickup_sheet.png` (1280x256: 5 cells of 256x256, each centered on the red cross; repacked from the 2172x724 master `health_pickup_sprite_sheet.png`, 576 master px per cell) via `sprites/health_pickup.tres`, looping 0-1-2-3-4 at 8 fps; the canister "breathes" (1.27x wider in frame 2, intended, not normalized). Scale 0.3675 (25% smaller than the first 0.49 pass, user request): canister ~42 px wide in frames 0/4, ~54 px in frame 2, sparkles/base up to ~75x84 px. No spin (`spin = false`); collision circle shrunk with the art, r 28 -> 21 (42 px, the smallest canister width). Sheet imported with mipmaps like the shield sheet | swapped |
| Shield bubble pickup | `scenes/collectibles/shield_pickup.tscn` `AnimatedSprite2D` `sprite_frames` / `scale` (note in `scripts/collectibles/shield_pickup.gd`) | — | `sprites/shield_icon_sheet.png` (1280x256: 5 cells of 256x256, the hex sphere centered and the same size in every cell, rim radius ~90 px; repacked from the 2172x724 glow-pulse master `shield_icon_sprite_sheet.png`, 512 master px per cell) via `sprites/shield_icon.tres`, looping 0-1-2-3-4 at 8 fps; scale 0.3 = ~55 px sphere on screen (glow up to ~72 px). No shader material (the art has its own glow), no spin (`spin = false`); collision circle r 28 unchanged | swapped |
| Screen-clear bomb pickup | `scenes/collectibles/bomb_pickup.tscn` Sprite2D `texture` / `scale` / `position` (note in `scripts/collectibles/bomb_pickup.gd`) | — | `sprites/bomb_collectible_1.png` (560x512, master 1312x1199) at Sprite2D scale 0.1, ~56x51 px canvas, offset (6, -6) so the round body sits on the pickup center / spin axis; collision circle r 28 unchanged (optional later: 2-frame spark flicker as hframes) | swapped |
| Player shield ring | `scenes/player.tscn` `ShieldRing/Dome` Sprite2D (note in `scripts/main_level/player.gd`); code drives ShieldRing's scale / modulate / visibility (pulse, hit pop, last-2 s blink) | — | `sprites/shield_dome_1.png` (634x634 full sphere, master 1254x1254) at scale 0.5258, position (0, -6) (within 5 local px of each ship's art center): sphere radius 126 local px, ~10 px outside the largest ship's farthest corner (and still outside at the -5% pulse); ~204 px sphere on screen at the Player's 0.8, halo to ~251 px. `shield_bubble.gdshader` with `interior_strength` 0.55 (faded hex pattern), cyan-white rim ring + halo (see "Shield look"). Old half-dome art kept in `art_archive/art_old/shield_dome_half.png` | swapped |
| Bomb screen flash, shield HUD indicator | `scripts/main_level.gd` `_start_bomb_flash()` (white ColorRect under `UI`, 0.25 s), `scenes/ui/game_hud_ui.tscn` `ShieldBox` | ColorRect fade, m5x7 "SHIELD" label + ProgressBar | None (code-only effects) | code-only |
| Enemy hit flash + scale punch | `shaders/hit_flash.gdshader` (assigned per instance in `scripts/obstacles/obstacle.gd` `_setup_hit_flash()`; driven by `_on_hit()` / `_update_hit_feedback()`) | White mix on the sprite (0.08 s) and a 1.12x scale punch (0.1 s) | None (code-only effect; works with any swapped enemy texture) | code-only |
| Enemy hit sparks | `scenes/effects/hit_spark.tscn` CPUParticles2D (marker in `scripts/effects/hit_spark.gd`) | 7 untextured white -> yellow squares, 0.25 s one-shot burst | 2-3 frame spark sheet, ~64x64 per frame, transparent PNG, white/yellow star; set as the particles `texture` with a CanvasItemMaterial using `particles_animation` (like `obstacle_explosion.tscn`) | placeholder |
| Enemy mini health bar | `scenes/effects/enemy_health_bar.tscn` `Back` / `Fill` ColorRects (marker in `scripts/effects/enemy_health_bar.gd`) | Dark 40x5 ColorRect back + red -> yellow ColorRect fill | None (code-only); optionally a 40x5 frame + fill texture (TextureProgressBar) | code-only |
| Enemy hit sound | `scripts/obstacles/obstacle.gd` `hit_sound` export (marker there; per-scene overrides possible) | `audio/retro-coin-1.mp3` at pitch 2.4, -16 dB, max one per 50 ms | Short hit tick, 0.1-0.2 s, mp3/ogg (dry, high, non-tonal so rapid repeats don't read as coins); reset `hit_sound_pitch` to 1.0 | placeholder |
