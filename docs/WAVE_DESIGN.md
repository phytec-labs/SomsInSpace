# Wave design

Enemy waves are authored data. Every run plays the same waves in the same order;
the only per-run variation is a left/right mirror of groups that allow it. The
goal is learnable arcade patterns rather than random clutter.

Code: `scripts/main_level/wave_manager.gd` (sequencer),
`scripts/main_level/formation_manager.gd` (formations, paths, fire patterns),
`scripts/main_level/spawn_manager.gd` (pooling and the obstacle cap).
Data: `data/zones/*.tres` (waves), `data/paths/*.tres` (entry paths),
`data/game_config.tres` (global caps).

## How a zone plays

For each wave of the zone, in order, and for each group of the wave, in order:

1. **Slot**: wait until fewer than the zone's formation cap are alive:
   `ZoneDefinition.max_formations_on_screen` if set (atmosphere and
   upper_atmosphere: 4), else `GameConfig.max_formations_on_screen` (3). A
   scene_override group counts as one formation.
2. **Telegraph** (if `telegraph`): a yellow chevron + "!" marker appears at the
   path's first point, pulled onto the screen edge and pointing along the path.
   It shows for `GameConfig.telegraph_seconds` (0.5 s, shortened by the ramp's
   beat multiplier, never below 0.3 s).
3. **Spawn**: all `count` members spawn together at the path start and fly the
   path as one formation. If the obstacle cap (`max_active_obstacles`, 60) is
   hit, the formation spawns with fewer members. If nothing spawns, the group is
   retried every 0.25 s.
4. **Release** of the next group:
   - `ON_CLEAR`: wait until every member of this group is dead or off screen,
     then `beat_after` seconds.
   - `AFTER_DELAY`: wait `delay` seconds after this group spawned. Its members
     may still be alive. Use this for deliberate overlaps like pincers and escorts.

After the last group, the wave waits until every group it spawned is cleared,
then `completion_delay` seconds, then the next wave starts. Exception: a
`scene_override` group released `AFTER_DELAY` (the UFO leading an escort) does
not hold the wave. The single keeps flying on its own (and keeps its formation
slot while alive), but the wave completes once its formation groups are
cleared. A `scene_override` group released `ON_CLEAR` still holds the wave.
The zone's mini-boss (the atmosphere blimp) is not in the wave list at all;
see "Mini-boss" below. After the last wave
the zone loops from the first wave. `one_shot` groups that already spawned
during this visit are skipped. Changing zone restarts the sequence at wave 0
with ramp 0. Formations already flying keep flying. Zones without waves (the
orbit/boss zone) spawn nothing. Defeating the boss ends the run with the
victory landing (~7.5 s to the results: station descends, the ship shrinks
onto its landing pad, touchdown ring + flash + shake, DOCKED); the timeline
and its exported timings are in `scripts/effects/docking_station.gd`.

### Difficulty ramp (adds speed, never bodies)

`ramp level = int(time in zone / ramp_interval_seconds)` (25 s). Per level:

- path and descend speeds × `ramp_speed_multiplier` (1.1, capped at
  `max_speed_multiplier` 1.6). HOLD_THEN_DESCEND hover time is divided by the
  same factor.
- beats, delays, completion delays and the telegraph × `ramp_beat_multiplier`
  (0.9, floored at `min_beat_multiplier` 0.5).

Counts never change. Self-moving singles (blimp, UFO) keep their own speeds.
The HUD threat indicator shows the ramp level (`WaveManager.get_ramp_level()`).

### Mini-boss (zone-level, anchored to the weapon upgrade)

A zone can name one mini-boss (`ZoneDefinition` group "Mini-boss"; today only
the atmosphere: the blimp). It is not a wave group, so its arrival no longer
depends on how fast the earlier waves are cleared. Once per zone visit:

1. **Schedule**: when the zone's weapon upgrade is collected,
   `main_level.gd` (`_on_weapon_upgrade_collected()`, only for the pickup
   spawned in the current zone) calls
   `spawn_manager.wave_manager.notify_weapon_upgrade_collected()`; the
   mini-boss is due `miniboss_delay_after_upgrade` (2.5 s) later. If that has
   not happened by zone time `miniboss_fallback_zone_time` (18 s; the player
   ignores the pickup, or the zone spawned none because the weapon is already
   at max tier), it is due then. Whichever comes first wins.
2. **Telegraph**: the usual marker at the top center shows during the last
   `telegraph_seconds` before it is due.
3. **Spawn** (exactly when due): `FormationManager.create_single_group()`
   with a runtime scene_override group at the `hover_top` start (360, -102),
   like the old one_shot wave group: pooled, subject to the obstacle cap
   (retried every 0.25 s), zone health multiplier applied, `object_spawned`
   emitted, and it takes a formation slot while alive. It does not wait for a
   free formation slot (so it keeps its 2.5 s promise): if the zone's cap is
   already full it is briefly one formation over it (seen in 2 of 3 seeds:
   4 wave formations + the blimp). The sequencer itself never exceeds the
   cap, and counts the mini-boss. `WaveManager.miniboss_spawned` is emitted.
4. **Hold** (`miniboss_holds_waves`): while it is alive, the sequencer
   finishes the group it is releasing (slot wait / telegraph) but starts no
   new group or wave (state `HOLD`); formations already on screen keep
   flying. When it is dead or gone, the sequence resumes after a 0.6 s beat
   (`MINIBOSS_RESUME_BEAT`, x the ramp's beat multiplier). The hold never
   lasts past `miniboss_hold_max_seconds` (8 s) after the spawn: then the
   sequencer resumes at once and releases groups alongside the live
   mini-boss (which still takes a formation slot).

A zone change cancels a mini-boss that is still pending (or telegraphing); a
live one keeps flying like any formation and no longer holds the new zone's
sequencer. All timing runs on `WaveManager.zone_time` (an accumulator in
`_process()`), so pausing freezes it. The blimp's energy + health cell drops
are unchanged.

## Data model

### WaveGroup (`scripts/data/wave_group.gd`)

| Field | Meaning |
|---|---|
| `enemy_scene` | The one enemy type of this formation |
| `formation` | Shape: LINE, V_SHAPE, SQUARE, DIAGONAL, WAVE, CIRCLE, RANDOM, SWARM |
| `count` | Members in this formation (scene_override: number of singles) |
| `spread` | Member spacing in px; 0 = zone `FormationSettings.default_spread` (SWARM: scatter radius, 0 = `swarm_radius`) |
| `path` | EntryPath id (`data/paths/<id>.tres`) |
| `path_speed` | px/s along the path; 0 = the path's `default_speed` |
| `hold_seconds` | Hover time on HOLD_THEN_DESCEND paths; 0 = the path's `hold_seconds` |
| `mirror_allowed` | 50% chance per spawn to mirror the path and the offsets about the screen center |
| `force_mirror` | Always mirror (the right half of a pincer). Overrides `mirror_allowed` |
| `fire_mode` | NONE, VOLLEY, RIPPLE, INDIVIDUAL (see below) |
| `fire_interval` | Seconds between volleys / ripples |
| `first_fire_delay` | Seconds from the first member appearing on screen to the first volley / ripple (0.6); later ones follow every `fire_interval` |
| `release` | ON_CLEAR or AFTER_DELAY (see above) |
| `delay` | AFTER_DELAY: seconds after spawning before the next group |
| `beat_after` | ON_CLEAR: pause after the group is cleared |
| `telegraph` | Show the warning marker before spawning (default on) |
| `scene_override` | Spawn `count` single self-moving instances of this scene (blimp, UFO) at the path's start point, with no formation or path motion. With AFTER_DELAY the singles don't hold wave completion |
| `one_shot` | Spawn at most once per zone visit |

### Fire modes

| Mode | Behaviour |
|---|---|
| NONE | Members never shoot |
| VOLLEY | `first_fire_delay` after the first member is on screen, then every `fire_interval`: every live on-screen member with `can_shoot` fires at once |
| RIPPLE | Same clock as VOLLEY; members fire one after another in index order, 0.12 s apart |
| INDIVIDUAL | Members use the old per-frame random shooting (`Obstacle._process_shooting`) |

The fire clock only starts once a member is on screen (inside the viewport),
so a formation that takes a while to fly in doesn't open fire the moment it
appears, and doesn't wait a whole `fire_interval` either.

Individual shooters (INDIVIDUAL members, boss minions) take their first shot
`Obstacle.first_shot_delay` (0.5 s) after spawning, and only while on screen
(below the top edge, inside the sides); after that the usual 1-3 s random
cooldown and the per-frame `shoot_chance` roll apply (so a `shoot_chance` of
0.01 still adds ~1.7 s on average). The blimp schedules its own shots: first
one `first_shot_delay` = 0.8 s after spawning (set in `blimp_obstacle.tscn`)
once the turret mount is below the top edge, then every `shot_interval`.

Formation fire sets `Obstacle.fire_controlled`, which disables the random
shooting. Only members on screen fire. Members whose scene has
`can_shoot = false` never fire (e.g. `satellite_obstacle_*`); use a shooting
variant for a firing formation (`satellite_turret_obstacle.tscn`: satellite_1
with `can_shoot`, a `GunPoint1` and aimed shots). A member may override
`shoot()` to fire a pattern instead of one aimed shot: the scout saucer fires
a three-shot fan on each volley (see "UFO weapons and scout saucers").
Blimp, UFO and boss minions manage their own shooting and are never
fire-controlled.

### EntryPath (`scripts/data/entry_path.gd`)

| Field | Meaning |
|---|---|
| `id` | Name used by `WaveGroup.path` |
| `curve` | Curve2D in normalized screen space: x 0..1 of width, y 0..1 of height; y < 0 is above the screen, x < 0 or > 1 is beyond a side |
| `default_speed` | px/s along the curve |
| `end_mode` | DESCEND (fall straight down), HOLD_THEN_DESCEND (hover with sway, then descend), EXIT (keep flying along the last tangent until off screen) |
| `hold_seconds`, `hold_sway_amplitude` | Hover time and x sway (px) for HOLD_THEN_DESCEND |
| `descend_speed` | px/s of the straight descent |

Paths are authored left-handed. Right-hand variants come from mirroring, not
from separate files. Members sit at path point + formation offset, and SWARM
adds a sway and per-member jitter. Members that leave the screen after having
been on it are released to the pool.

#### Path library (`data/paths/`)

| Path | Speed / descend | Shape |
|---|---|---|
| `top_straight` | 240 / 170 | Straight down from top center to y 0.35, then descend |
| `swoop_left` | 300 / 190 | Enters above the top-left, arcs to the right at y 0.25, curls back to center (y 0.4), then descends |
| `loop_left` | 300 / 190 | Enters top-left, flies one full loop around (0.4, 0.3), then descends |
| `pincer_left` | 280 / 190 | Enters from the left edge at y 0.15, curves in toward center (0.4, 0.35), then descends. Pair it with a `force_mirror` copy for a pincer |
| `side_sweep_left` | 260 / exit | Enters from the left at y 0.3, sweeps across to beyond the right edge at y 0.4, then exits |
| `hover_top` | 220 / 160 | Drops from top center to y 0.22, hovers 6 s with a 60 px sway, then descends |
| `dive_center` | 440 / 440 | Fast straight dive from the top, slanting toward center |

### ZoneDefinition (`scripts/data/zone_definition.gd`)

`waves` (the sequence) and `formation_settings`. `max_formations_on_screen`
(group "Spawning") is the zone's formation cap; 0 (the default: ground,
space, orbit) uses `GameConfig.max_formations_on_screen`. It only matters in
zones whose waves overlap groups (AFTER_DELAY), since a wave never overlaps the
next one (see "How a zone plays"). `obstacle_scenes` and the
movement pattern weights are only used by the legacy `spawn_obstacle()` and by
boss minions. Ramp: `ramp_interval_seconds` (25), `ramp_speed_multiplier` (1.1),
`max_speed_multiplier` (1.6), `ramp_beat_multiplier` (0.9),
`min_beat_multiplier` (0.5).

Mini-boss fields (group "Mini-boss"; see "Mini-boss" above):

| Field | Default | Atmosphere | Meaning |
|---|---|---|---|
| `miniboss_scene` | null | `blimp_obstacle.tscn` | Self-moving mini-boss spawned once per zone visit at the top center; null = none |
| `miniboss_delay_after_upgrade` | 2.5 | 2.5 | Seconds from collecting the zone's weapon upgrade to the spawn (telegraph in the last 0.5 s) |
| `miniboss_fallback_zone_time` | 18.0 | 18.0 | Zone time at which it spawns anyway (upgrade not collected / none spawned); 0 = no fallback |
| `miniboss_holds_waves` | true | true | No new group is released while it is alive |
| `miniboss_hold_max_seconds` | 8.0 | 8.0 | Hold cap, counted from the spawn: past it the waves resume alongside the live mini-boss; 0 = hold until it is gone |

`enemy_health_multiplier` (group "Difficulty") scales the health of every
obstacle the SpawnManager spawns in the zone: formation members,
scene_override singles (blimp, UFO), mines, asteroids and their split pieces,
and boss minions. It is applied on every spawn (`Obstacle.health_scale`, set
before `initialize()`), so pooled instances reused in another zone get that
zone's value. Bosses (`spawn_boss()`) and collectibles are never scaled.

| Zone | Multiplier | Typical enemy (10 hp base) | Balanced / light / heavy hits at tier 1 |
|---|---|---|---|
| ground | 1.0 | 10 | 1 / 2 / 1 |
| atmosphere | 2.0 | 20 | 2 / 3 / 2 |
| upper_atmosphere | 2.5 | 25 | 3 / 3 / 2 |
| space | 3.0 | 30 | 3 / 4 / 3 |
| orbit | 1.0 | 10 (boss minions) | 1 / 2 / 1 |

Tier-1 damage per shot: balanced (phyCORE-AM62x) 10 every 0.2 s, light
(i.MX 93) 8.5 every 0.16 s, heavy (i.MX 8M Plus) 12.5 every 0.23 s. Tier 2
adds two side shots (3 per volley), tier 3 two angled 12-damage shots. Base
health that differs from 10: drone 5, mine 8, asteroid 30 / 15 / 6 (large /
medium / small), UFO 170 (425 in upper_atmosphere, 510 in space), scout
saucer 50 (150 in space, its only zone), blimp 270 (540 in the atmosphere, its
only zone).

Big targets, balanced ship, sustained fire (headless, ship tracking the
target from 250-800 px below; seconds from the first hit to the kill):

| Target | Health | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|---|
| Blimp (atmosphere) | 540 (was 320) | ~10.8 s (54 hits) | ~4.0-4.4 s (was ~2.7-3.3 s) | ~3.3-4.1 s |
| UFO (upper_atmosphere) | 425 (was 200, before that 100) | | ~4.6 s median, 3.9-5.6 s (was ~2.1-2.4 s) | ~4.3 s median, 3.2-4.7 s (was ~1.7-2.5 s) |
| UFO (space) | 510 (was 240, before that 120) | | ~5.1 s median, 4.7-6.3 s (was ~2.5 s) | ~4.3 s median, 3.4-5.2 s (was ~1.9-2.9 s) |
| Scout saucer (space) | 150 | | ~1.55 s median, 1.0-1.55 s | ~1.33 s median, 0.8-1.5 s |

The Player node is scaled 0.8 in the level, so the balanced ship's wing guns
sit at about +-30 px on screen. The blimp's hull (capsule radius 40, ~94 px
wide sprite) takes all three tier-2 shots while the ship is within about
+-15 px of its center (2 per volley at +-20 px and beyond; the earlier
radius-30 hull only within about +-6 px). The tier-3 angled shots mostly
miss it, so tier 3 is only a little faster. The UFO is 200 px wide, so all
three tier-2 shots land; its sideways patrol and the ~1.5 s shot travel time
cost some hits. (UFO rows: 16 trials per cell, ship 1050 px from the top
tracking the saucer every frame, base 170 measured 2026-10. Scout row: 8
trials per cell, a stationary scout at y 300, ship 1050 px from the top
within +-28 px of its x, continuous fire, seconds from the first hit; the
scout's 120 px capsule takes all three tier-2 shots, so tier 3 adds little.)

UFO, casual player (same ship at y 1050; the saucer flies in from above as in
a real spawn; the ship moves at its own speed toward the saucer's x plus a
wobble re-rolled every 0.7 s; fires 1.2 s on / 0.8 s off = 60%; 40 trials per
cell). Seconds from the start of the hover to the kill (hits taken during the
fly-in count), and how often it ends its 12 s hover alive and leaves:

| Zone (health) | Aim wobble | Tier 2 | Tier 3 |
|---|---|---|---|
| upper_atmosphere (425) | +-60 px | median 6.9 s (4.4-11.4), escaped 0/40 | median 5.1 s (2.7-8.2), escaped 0/40 |
| upper_atmosphere (425) | +-100 px | median 7.5 s (4.6-11.9), escaped 4/40 | median 5.3 s (2.9-10.3), escaped 0/40 |
| space (510) | +-60 px | median 7.6 s (4.8-11.7), escaped 1/40 | median 6.0 s (3.6-9.9), escaped 0/40 |
| space (510) | +-100 px | median 7.7 s (5.3-11.5), escaped 4/40 | median 6.3 s (3.1-10.2), escaped 0/40 |

A casual tier-3 player always kills it inside the hover; at tier 2 a sloppy
player lets about 1 in 10 escape (acceptable: it is a bonus target, not a
gate). Tier 3 is only ~10-25% faster than tier 2 because the angled shots
mostly miss the 52 px tall hull.

### FormationSettings (`scripts/data/formation_settings.gd`)

`default_spread`, plus the swarm fields `swarm_radius`, `swarm_sine_amplitude`,
`swarm_sine_frequency` (sway around the path), and `swarm_jitter_*`.
Defaults: radius 165, sway 50 px at 1.5 rad/s, jitter 6 px (6-8 drones stay
~48+ px apart). A swarm's center is kept far enough from the screen sides that
no member leaves them (except on EXIT paths such as `side_sweep_left`), and a
path that starts off screen gets a straight lead-in so the whole swarm starts
off screen.

### GameConfig caps

`max_active_obstacles = 60`, `max_formations_on_screen = 3` (default for
zones that leave their own cap at 0), `telegraph_seconds = 0.5`.

## Difficulty knobs

The values play-testing usually touches, and where they live:

| Knob | Where | Current | Effect |
|---|---|---|---|
| `enemy_health_multiplier` | each `data/zones/<zone>.tres` | ground 1.0, atmosphere 2.0, upper_atmosphere 2.5, space 3.0, orbit 1.0 | Hits to kill every non-boss enemy in the zone (table above) |
| Boss health | `scenes/obstacles/boss_alien.tscn` `health` | 750 | Fight length; phases change at 2/3 and 1/3 of it automatically (~16.5 s with the sweeping tier-2 bot; ~20 s for the casual tier-3 bot with the minion / orb pressure, see "Orbit: the boss fight") |
| Boss minions / orbs | `scripts/obstacles/boss_alien.gd` `PHASES` (`summon`, `summon_count`, `orbs`, `orb_count`), exports `max_minions`, `first_summon_delay`, `max_orbs` | see "Orbit: the boss fight" | Bodies and homing threats in the fight |
| Zeppelin missiles | `scripts/obstacles/blimp_obstacle.gd` group "Blimp Missiles" | pair every 4.5 s, max 4 live | See "Missiles" |
| Blimp health | `scenes/obstacles/blimp_obstacle.tscn` `health` | 270 (x 2.0 in atmosphere = 540) | Mini-boss length (~4.0-4.4 s of sustained tier-2 fire, ~10-12 s for the casual bot) |
| UFO health | `scenes/obstacles/ufo_obstacle.tscn` `health` | 170 (x 2.5 = 425 upper_atmosphere, x 3.0 = 510 space) | ~4.3 s of sustained tier-3 fire in space (~5 s tier 2); a casual player (60% fire, loose aim) needs ~5-8 s of its 12 s hover; raise it and the casual escape rate climbs fast |
| UFO weapons | `scripts/obstacles/ufo_obstacle.gd` group "UFO Weapons" | ring of 12 at 150 px/s every 3.0 s (first 1.5 s into the hover, 0.4 s tell); bolt 25 after 1.5 s in the beam, 2.0 s cooldown | See "UFO weapons and scout saucers" |
| Scout saucer | `scenes/obstacles/scout_ufo_obstacle.tscn` (`health` 50, fan exports in `scout_ufo_obstacle.gd`), group in `data/zones/space.tres` "Minefield" | 150 in space; fan of 3 at +-18 deg, 360 px/s; VOLLEY every 2.2 s, hold 4 s | ~1.3 s of sustained tier-3 fire each |
| Mini-boss timing | `data/zones/atmosphere.tres`, group "Mini-boss" | 2.5 s after the upgrade is collected, fallback 18 s zone time, holds waves for at most 8 s | When the blimp arrives and how long the sequencer pauses for it |
| `first_fire_delay` | each `WaveGroup` | 0.6 s | Formation's first volley / ripple after it appears on screen |
| `fire_interval` | each `WaveGroup` | 1.2-2.5 s | Time between formation volleys / ripples |
| `first_shot_delay` | `Obstacle` export (per scene) | 0.5 s (blimp 0.8 s) | Individual shooters' first shot after spawning (only once on screen) |
| Ramp fields | each zone, "Difficulty Ramp" | 25 s, x1.1 (max 1.6), x0.9 (min 0.5) | How fast a zone speeds up while the player stays in it |
| `max_active_obstacles` | `data/game_config.tres` | 60 | Hard cap on live obstacles (safety valve) |
| `max_formations_on_screen` | `data/game_config.tres`, overridden per zone in `data/zones/<zone>.tres` | 3; atmosphere and upper_atmosphere 4 | How many formations may overlap |

### Enemy readability

Dark enemies on the dark upper-atmosphere and space skies get two per-zone
shader effects (group "Enemy Readability" on each `data/zones/<zone>.tres`,
applied by `shaders/hit_flash.gdshader`, the per-enemy material that also
does the hit flash; the hit flash still goes to pure white on top):

| Field | ground | atmosphere | upper_atmosphere | space | orbit |
|---|---|---|---|---|---|
| `enemy_brighten` | 0 | 0 | 1.0 | 1.0 | 1.0 |
| `enemy_rim_strength` | 0 | 0.2 | 0.45 | 0.55 | 0.55 |
| `enemy_rim_color` | - | warm white (1, 0.96, 0.88) | cool white-cyan (0.75, 0.95, 1) | pale blue (0.7, 0.85, 1) | as space |

- `enemy_brighten`: 0 = the original enemy shading (the shader multiplied
  the texture in twice, i.e. the art's colours squared: darker and punchier,
  which suits the light ground sky; ground looks exactly as before), 1 = the
  art's own colours. In between blends the two.
- `enemy_rim_strength` / `enemy_rim_color`: an inner rim light along each
  enemy's silhouette edge (inside the sprite, so canvas-edge art gets one
  too), a constant `Obstacle.rim_screen_px` = 2 screen px wide whatever the
  sprite's scale (the shader width is recomputed per spawn as
  `rim_screen_px / sprite global scale`; asteroid size changes refresh it).
  0 = off. Sprite-sheet frames (alien, plane) are clamped to their own frame.
- SpawnManager sets the zone's values on every spawn (pooled reuse included);
  enemies still flying at a zone change blend to the new zone's values over
  `SpawnManager.readability_blend_seconds` (1.5 s; the sky wipe takes 2.5 s).
- The boss takes the zone's brighten (its hue-shift shader has the same
  uniforms: 1 = the intended bright magenta, 0 = the old dark maroon) but not
  the rim (`use_zone_rim = false` on the boss scene; a rim on its big
  pixel-art silhouette reads as an outline). Any enemy can opt out the same way.
- Cost: both effects sit behind uniform branches; brighten < 1 costs one extra
  texture sample (the original shader's cost), the rim four more samples.

## Adding or editing a wave

1. Open the zone in the Godot inspector (`data/zones/<zone>.tres`), then open
   `waves`.
2. Add a WaveDefinition (name, `completion_delay`) and add WaveGroups to its
   `groups`, in play order.
3. For each group, set `enemy_scene`, `formation`, `count` and `path`. Use
   `spread`, `path_speed` and `hold_seconds` only to override the defaults.
4. Choose the release. Keep ON_CLEAR as the default, since it is what keeps the
   screen readable. Use AFTER_DELAY with a small `delay` only for deliberate
   overlaps: pincer halves, an escort behind a UFO, or a follow-up line. Every
   AFTER_DELAY group adds a formation to the screen at once, and the zone's
   formation cap (3, or the zone's own `max_formations_on_screen`) still
   applies. Overlap only happens inside a wave: a wave with two groups never
   shows more than two formations, whatever the cap.
5. For a symmetric pincer, add two groups with the same path. Set the first to
   `mirror_allowed = false` and AFTER_DELAY 0. Set the second to
   `force_mirror = true`.
6. A new path needs a new `EntryPath` resource in `data/paths/`. Author it
   left-handed in normalized coordinates, start it off screen (y < 0 or x < 0),
   and keep the on-screen part inside x 0.1..0.9 so formation offsets don't
   clip the sides.
7. The first wave of a zone should be the simplest: one formation with no fire.

## Authored waves

Times are bot loop times at ramp 0 (headless harness, invulnerable bot sweeping
side to side, balanced ship, tier-2 auto-fire, `--fixed-fps 60`, zone held with
scroll 0, seeds 1-3), measured 2026-09 with the zone health multipliers. They
vary by a few seconds between runs (mirror rolls, physics). They were measured
before the blimp became the zone's mini-boss (it was then a wave of its own);
the mini-boss now adds its hold to whichever wave is playing when it arrives
(see the timeline below). The bot usually kills the UFO within a few seconds
(at 200 hp; at today's 425 / 510 see the UFO tables above);
a UFO left alive lives ~22 s, which does not hold its wave (see above).
C = `completion_delay`; beat = `beat_after`. Groups are ON_CLEAR unless an
AFTER_DELAY value is given.

In a normal run (100 m/s) a zone lasts ground 15 s, atmosphere 35 s,
upper_atmosphere 50 s, space 35 s, so only the first waves of each list are
seen: atmosphere Jet Swoop, Pincer, Crossfire Lite (the blimp arrives in the
middle of them, see below); upper_atmosphere Jet Loop, Meteor Dive, Saucer
Escort, Meteor Storm and Satellite Grid (from ~39-46 s). Keep that in mind
when inserting a wave.

#### Normal-run timeline (blimp and UFO beats)

Headless, `--fixed-fps 60`, normal scroll (100 m/s), balanced ship, seeds
1-3, "casual" bot: sweeps / tracks the nearest enemy at ship speed, fires 60%
of the time (1.2 s on, 0.8 s off), aims at a blimp / UFO once it is on screen
(+-20 px wobble), fetches each weapon upgrade 2 s after it settles. Seconds
from the start of the run (the 3 s countdown excluded):

| Event | Before (blimp = wave 4) | After (mini-boss) |
|---|---|---|
| Atmosphere entry | 15.0 | 15.0 |
| Upgrade spawn / settled / collected | 15.0 / 23.8 / 27.3-27.4 | same |
| Blimp spawn | 45.2-46.6 (18-19 s after the upgrade, 4-5 s before the next zone's upgrade) | 29.8-29.9 (2.50 s after the upgrade) |
| Blimp first visible / center on screen | +0.4 s / +3.8-4.1 s after spawn | same |
| Blimp killed (tier 2 at spawn) | 54.4-57.6 (6.5-9.7 s of fire; 320 hp; killed after upper_atmosphere started) | 40.1 / 40.4 / 42.0 (9.9-12.1 s of fire; 540 hp, larger hull) |
| Sequencer hold (no new group) | wave held until the blimp died or the zone changed | seeds 1-2: none (the next release came after the 8 s cap); seed 3: 30.7-37.9 (ended by the 8 s cap) |
| Upper atmosphere entry, upgrade spawn / collected | 50.0, 50.0 / 62.3-62.4 | same |
| First UFO spawn / kill (tier 3) | 69.2-71.2 / +1.1-3.0 s (100 hp) | 69.4-70.2 / +1.5-4.0 s (200 hp) |

Other cases (after): the bot never collects the upgrade -> blimp at zone time
18.0 (run time 33.0); atmosphere entered at tier 3 (no upgrade spawns) ->
blimp at 33.0, killed 9.5 s later; a bot that never shoots the blimp -> the
hold ends 8.0 s after its spawn and groups are released alongside it while
it lives; the bot stops at tier 2 -> first UFO (200 hp) killed 2.9 s after
spawning (it hovers 12 s). Exactly one blimp per atmosphere visit in every
run.

Attract demo (autopilot focuses a mini-boss on screen, seeds 1-4 and 9): the
blimp arrives 2.5 s after the demo takes the upgrade, lives 8.5-14.9 s
(median 12.9 s; dodges and pickup fetches take 7-43% / 0-29% of that time)
and holds the waves 6.8-7.4 s.

### Ground (spread 90; loop ≈ 14 s)

| Wave | Groups | C |
|---|---|---|
| 1 Welcome | 3 × balloon_1 LINE `top_straight` (spread 110), NONE, beat 0.4 | 0.5 |
| 2 Planes | 4 × plane_1 V_SHAPE `swoop_left` (mirror), NONE, beat 0.4 | 0.5 |
| 3 Swarm | 6 × drone SWARM `side_sweep_left` (mirror), NONE, beat 0.6 | 1.0 |

### Atmosphere (spread 100, formation cap 4; loop ≈ 41-48 s, plus the mini-boss hold in the loop it arrives in)

Groups follow each other quickly (AFTER_DELAY 1.0-1.5 s) so three, sometimes
four, formations share the screen; beats are 0.6 s and completion delays
0.8 s. The blimp is the zone's mini-boss (not in this list): it enters 2.5 s
after the weapon upgrade is collected (at the latest at 18 s zone time) and
holds new groups while it is alive, for at most 8 s.

| Wave | Groups | C |
|---|---|---|
| 1 Jet Swoop | 5 × jet_1 V `swoop_left` RIPPLE 2.0, AFTER_DELAY 1.5 → 3 × balloon_5 LINE `top_straight` (spread 120), NONE, AFTER_DELAY 1.0 | 0.8 |
| 2 Pincer | 3 × jet_2 DIAGONAL `pincer_left` (no mirror) VOLLEY 2.5, AFTER_DELAY 0 → 3 × jet_2 DIAGONAL `pincer_left` force_mirror VOLLEY 2.5, AFTER_DELAY 1.0 → 6 × drone SWARM `swoop_left`, AFTER_DELAY 1.0 → 3 × balloon_5 LINE `top_straight` (spread 120), beat 0.6 | 0.8 |
| 3 Crossfire Lite | 4 × jet_1 V `swoop_left` RIPPLE 2.0, AFTER_DELAY 1.0 → 4 × balloon_5 LINE `top_straight` (spread 120), AFTER_DELAY 1.5 → 6 × drone SWARM `side_sweep_left`, beat 0.6 | 0.8 |
| 4 Drone Loop | 7 × drone SWARM `loop_left`, AFTER_DELAY 1.2 → 4 × plane_1 V `swoop_left`, AFTER_DELAY 1.0 → 3 × balloon_5 LINE `top_straight` (spread 120), beat 0.6 | 0.8 |
| 5 Turrets | 4 × balloon_3 LINE `hover_top` hold 6 s (spread 120) VOLLEY 2.0, AFTER_DELAY 1.5 → 4 × jet_2 V `swoop_left` RIPPLE 2.0, AFTER_DELAY 1.5 → 6 × drone SWARM `side_sweep_left`, beat 0.6 | 1.0 |

### Upper atmosphere (spread 100, formation cap 4; loop ≈ 75-82 s)

Same pacing as the atmosphere: AFTER_DELAY 0.8-1.5 s, beats 0.6 s, completion
delays 0.8-1.0 s.

| Wave | Groups | C |
|---|---|---|
| 1 Jet Loop | 6 × jet_1 DIAGONAL `loop_left` (spread 110) RIPPLE 1.8, AFTER_DELAY 1.5 → 6 × drone SWARM `side_sweep_left`, beat 0.6 | 0.8 |
| 2 Meteor Dive | 5 × meteor_1 LINE `dive_center` (spread 110), AFTER_DELAY 1.2 → 5 × meteor_2 LINE `dive_center` force_mirror, AFTER_DELAY 1.0 → 4 × jet_1 V `swoop_left` RIPPLE 1.8, beat 0.6 | 0.8 |
| 3 Saucer Escort | 1 × UFO (scene_override, does not hold the wave), AFTER_DELAY 1.0 → 4 × jet_2 V `pincer_left` VOLLEY 2.2, AFTER_DELAY 1.0 → 4 × jet_2 V `pincer_left` force_mirror VOLLEY 2.2, beat 0.6 | 0.8 |
| 4 Meteor Storm | 5 × meteor_1 LINE `dive_center` (spread 110, no mirror), AFTER_DELAY 0.8 → 5 × meteor_2 LINE `dive_center` force_mirror, AFTER_DELAY 1.0 → 4 × jet_1 V `loop_left` VOLLEY 2.0, AFTER_DELAY 1.5 → 2 × asteroid LINE `top_straight` (spread 200), beat 0.6 | 1.0 |
| 5 Satellite Grid | 4 × satellite_turret SQUARE `hover_top` hold 5 s (spread 120) VOLLEY 1.8, AFTER_DELAY 1.5 → 6 × drone SWARM `swoop_left`, beat 0.6 | 0.8 |
| 6 Asteroids | 3 × asteroid LINE `top_straight` (spread 200), NONE, AFTER_DELAY 1.5 → 5 × meteor_1 LINE `dive_center` (spread 110), beat 0.6 | 0.8 |
| 7 Swarm Strike | 6 × drone SWARM `swoop_left`, AFTER_DELAY 1.0 → 3 × jet_8 LINE `dive_center` (spread 100) RIPPLE 1.2, AFTER_DELAY 1.0 → 4 × jet_1 V `loop_left` RIPPLE 1.8, beat 0.6 | 0.8 |
| 8 Crossfire | 5 × jet_9 WAVE `side_sweep_left` (spread 70) RIPPLE 1.6, AFTER_DELAY 1.5 → 5 × jet_9 WAVE `side_sweep_left` force_mirror RIPPLE 1.6, beat 0.6 | 1.0 |

### Space (spread 110; loop ≈ 46-51 s, measured with the satellites)

Satellites belong to the upper atmosphere only: the space "Minefield" wave's
two satellite sweeps were replaced by one V of scout saucers (2026-10), and
the zone's legacy `obstacle_scenes` list names the scout instead of the
satellites.

| Wave | Groups | C |
|---|---|---|
| 1 Alien Swoop | 5 × alien V `swoop_left` VOLLEY 2.0, beat 0.8 | 1.0 |
| 2 Minefield | 5 × mine LINE `top_straight` (spread 130), NONE, AFTER_DELAY 0.5 → 3 × scout saucer V `hover_top` (spread 150) hold 4 s VOLLEY 2.2 (first 0.6 s), beat 0.8 | 1.0 |
| 3 Saucer Rocks | 1 × UFO (scene_override, does not hold the wave), AFTER_DELAY 1.0 → 2 × asteroid LINE `dive_center` (spread 160), AFTER_DELAY 2.5 → 2 × asteroid LINE `dive_center` force_mirror, beat 0.8 | 1.0 |
| 4 Alien Ring | 8 × alien CIRCLE `hover_top` hold 6 s (spread 110) RIPPLE 1.5, beat 0.8 | 1.0 |
| 5 Jet Pincer | 3 × jet_8 V `pincer_left` (no mirror) VOLLEY 2.0, AFTER_DELAY 0 → 3 × jet_9 V `pincer_left` force_mirror VOLLEY 2.0, AFTER_DELAY 1.5 → 8 × drone SWARM `loop_left` (380 px/s), beat 0.8 | 1.5 |

Orbit has no waves: the boss fight plays alone.

### Orbit: the boss fight

`scripts/obstacles/boss_alien.gd`. The Alien Mothership (750 health, no zone
multiplier) flies in for 2.5 s (shots absorbed), then fights in three phases
by health thirds. Per-phase data lives in its `PHASES` const:

| Phase | Health | Drift | Aimed shot | Fan volley | Minions | Seeker orbs |
|---|---|---|---|---|---|---|
| 1 | > 2/3 | 0.6 rad/s, 200 px | every 1.2 s | none | 2 every 7 s | none |
| 2 | > 1/3 | 1.0 rad/s, 220 px | every 1.5 s | every 2.0 s, 3 per gun point, all guns | 2 every 5 s | 2 every 5 s |
| 3 | rest | 1.5 rad/s, 230 px | every 1.2 s | every 1.0 s, one gun point at a time (L, C, R, C) | 3 every 3.5 s | 3 every 4 s |

- **Minions** (`minion_scene`, the alien, one-hit fodder: orbit's
  `enemy_health_multiplier` 1.0) spawn in every phase, ramping up to antagonize
  the player: the first summon comes `first_summon_delay` (2.5 s) after
  `fight_started`, later ones every phase interval; entering phase 2 or 3 puts
  the next summon half an interval away. At most `max_minions` (6) summoned
  minions alive (a summon only fills free slots), and they still go through
  `SpawnManager.spawn_minion()`, so `max_active_obstacles` applies.
- **Seeker orbs** (phases 2-3; see "Missiles" below) launch from the gun
  points with the attack animation, center first; at most `max_orbs` (5) in
  flight (a launch fires only what fits: with the 4.5 s fuse, phase 3
  alternates 3 and 2). On defeat (`_begin_death()`) and on `stand_down()` (the
  player died) the orbs in flight are removed without a burst (`clear_orbs()`);
  the boss's ordinary bullets keep flying as before (harmless: the level
  ignores damage once the run is over).
- Phase changes 2 and 3 drop a health cell below the boss and shake hard.

Casual-bot measurement (balanced ship, tier 3, 10 seeded runs each; bot fires
~60% of the time, aims at the nearest target with +-60 px wobble, sidesteps
shots within 120 px ahead; `--fixed-fps 60`), before -> after the minion / orb
change: fight 18.3 -> 19.8 s, health lost 25 -> 41 (healed 20 -> 31 by the
phase drops), minions 3.4 -> 12.3 per fight (3.3 -> 11.0 killed), orbs 7.5
shot down / 0.0 burst / 0.1 reached the player per fight, survival 10/10 ->
10/10 (lowest end health 90 -> 50). Tier 2: 46.0 s, health lost 78 (healed
53), 2.5 orbs burst per fight, 10/10 survive (lowest 35). Light ship (70
health) at tier 3: 19.7 s, 10/10 survive (lowest 45).

## UFO weapons and scout saucers

### UFO mini-boss (`scripts/obstacles/ufo_obstacle.gd`, group "UFO Weapons")

Both weapons work only while the saucer HOVERS (never while flying in or
leaving) and while the run is on; all timing is `_process` /
`_physics_process` delta, so they freeze while paused, and every value resets
on `initialize()` / `deactivate()` (pooled reuse).

- **Pulse ring.** `ring_first_delay` (1.5 s) after the hover starts, then every
  `ring_interval` (3.0 s): a `ring_telegraph` (0.4 s) tell, two quick pulses of
  the sprite's `self_modulate` toward `ring_telegraph_color` (the hull and
  lights flare; the hit flash still mixes to white after it in the shader),
  then `ring_bullets` (12) shots of `ring_scene` (`enemy_projectile_3.tscn`,
  the seeker-burst bullet) leave the hull's rim (`ring_rim_radius` 96 x 34
  ellipse) evenly spaced at `ring_speed` (150 px/s, `ring_lifetime` 9 s, both
  set per shot; the shot restores its authored 500 px/s when pooled). Every
  other ring is rotated by half a spacing (15 deg), so the gaps move. A full
  12 s hover fires 4 rings (1.5, 4.5, 7.5, 10.5 s); no tell is shown for a
  ring the hover would end before.
- **Charged bolt.** While the player stays inside the beam the charge rises
  over `charge_time` (1.5 s); outside the beam it drains in
  `charge_decay_time` (0.3 s). At full charge the beam fires: a
  `bolt_flash_time` (0.15 s) white flash down the whole beam and
  `bolt_damage` (25) through `level.update_health(-25, at)`: the shield
  absorbs it (pop + ripple, combo kept), the hit blink protects (no damage
  while blinking), otherwise the combo resets, the screen shakes as for any
  hit, the tier-loss option applies and the player starts blinking. Then
  `bolt_cooldown` (2.0 s) before charging can start again. The pull (220 px/s)
  and the drain (4 HP/s, halved by the shield) are unchanged.
- **Beam look.** The beam shader's `charge` uniform (the charge, 0..1) heats
  and narrows the core toward white and sends three bright bands down the
  beam as it rises; `bolt` (1 -> 0 over the flash) turns the whole cone white.
  See docs/ART_SWAP_TRACKER.md, "Beam look".
- **Escape time** (headless, ship starting on the beam's center line, dragged
  straight sideways at the same height, the pull acting; UFO at y 180, beam
  80-160 px wide): mid-height (y 460) 0.52 s balanced (300 px/s), 0.60 s
  heavy (240), 0.43 s light (380); at y 380 / 560: 0.48 / 0.53, 0.57 / 0.63,
  0.42 / 0.46 s. `charge_time` 1.5 s leaves the slowest ship ~0.9 s to react.
- Attract demo: the autopilot cruises below the beam (it ends at y ~710); if a
  pickup fetch takes it into a beam and the bolt starts charging
  (`is_charging()`), it escapes sideways 210 px from the saucer's x.

### Scout saucer (`scenes/obstacles/scout_ufo_obstacle.tscn`)

A medium formation enemy for the space zone only (it replaced the
satellites there). An ordinary pooled formation member (no beam, no hover
state machine): the mini-boss art at 60% size (Sprite2D scale 0.1247, ~126 px
wide), capsule 120 x 32 at y+4, `GunPoint1` at the underside emitter (0, 22).
Base health 50 (150 in space: ~1.3 s of sustained tier-3 fire), contact
damage 20, 40 points, no mini health bar (`show_health_bar = false`). Zone rim
and brighten, hit flash, sparks, pooling, the obstacle cap and combo points
work as for any enemy.

Weapon: each `shoot()` (the formation's VOLLEY calls it on every scout at
once) fires a fan of `fan_bullets` (3) shots at -18 / 0 / +18 deg
(`fan_spread_degrees`) around straight down from `GunPoint1`, red
`enemy_projectile_1.tscn` shots at `fan_speed` 360 px/s (other enemy shots
fly at 500) with `fan_lifetime` 4 s, both set per shot.

Art: `sprites/ufo_2.png`, the teal-lit second-colour render of the mini-boss
saucer (same silhouette), at the same scale as the hue-shifted stand-in it
replaced; `hue_shift` is back to 0 (the shader option stays, unused; see
docs/ART_SWAP_TRACKER.md).

### Balance (casual bot, balanced ship, tier 3)

Bot: fires ~60% of the time, aims at the nearest target with +-60 px wobble,
sidesteps shots within 120 px ahead and enemies within 140 px, reacts to
being caught in a beam after 0.4 s (steers 200 px sideways), fetches nearby
health / shield / missile pickups; `--fixed-fps 60`, 30 seeds per cell
(UFO) / 30 seeds (hold), before = commit 3cbe1b6.

UFO alone in space (510 health; the run continues until its last ring shot
is gone):

| Bot cruise height | Kill time median (range) | Health lost avg (max), before -> after | Rings | Bolts fired / hit | Beam escapes before a bolt |
|---|---|---|---|---|---|
| y 1024 (80%, default) | 7.8 s (5.0-14.2), unchanged | 0 (0) -> 7.3 (20) | 57 in 30 fights | 0 / 0 | 0 (never in the beam) |
| y 768 (60%) | 5.1 s (3.7-10.6), unchanged | 10.1 (26) -> 14.3 (52) | 37 | 3 / 3 | 85 |

Space zone held 60 s from its first wave (waves, the UFO of "Saucer Rocks",
pickups on; health 100):

| | Health lost avg (min-max) | Healed by pickups avg | Deaths | Kills avg | Satellites killed / escaped | Scouts killed / escaped | Peak obstacles | Peak enemy shots (avg of run peaks) | Formations max |
|---|---|---|---|---|---|---|---|---|---|
| Before (satellites, UFO without weapons) | 78.2 (10-160) | 21.0 | 6 / 30 | 54.8 | 216 / 126 | - | 14 | 13 (10.8) | 3 |
| After (scouts, UFO ring + bolt) | 81.2 (35-125) | 26.5 | 3 / 30 | 52.5 | - | 159 / 5 | 14 | 29 (21.6) | 3 |

The 60 s space hold already cost this bot ~78 health before the change (more
than the ~45 the zone was meant to cost a casual player); the scouts and the
UFO weapons leave it about where it was (+3, within run-to-run noise; fewer
deaths). The ring alone barely touches a player who stays low: its shots
spread out with distance and arrive slowly; it bites near the saucer, where
the beam pulls the ship.

## Pickups

Collectibles are not part of the wave data: the SpawnManager's collectible
timer (base 5 s x the zone's `collectible_time_scale`, spawn chance 0.7 x
`collectible_chance_scale`) spawns one pickup at a random x above the screen,
and `spawn_collectible()` rolls which one from the zone's pickup table.

| Pickup | Scene | Points | Effect |
|---|---|---|---|
| Energy coin | `energy_collectible_1.tscn` | 5 | Points only, flat (never multiplied by the combo). Gold "+5" popup starting 26 px above the coin (`main_level.gd` `_on_coin_collected()`: the text comes from the coin's `points`, `COIN_COLOR`, graze-sized `COIN_POPUP_SCALE` 0.7, offset `COIN_POPUP_OFFSET` (0, -26) so it clears the flash) plus a 0.24 s coin pop at the coin (`scenes/effects/coin_pop.tscn`: additive white-gold flash that collapses over the first 30%, expanding gold ring, six sparks; pooled). Drawn procedurally by `shaders/coin.gdshader` (spinning gold coin with an embossed five-point star by default, the `emblem` shader default; a darker groove keeps the star readable at every open phase; see ART_SWAP_TRACKER.md, "Coin look"); each coin spins with its own random phase and speed and twinkles on its own cycle (`twinkle_phase`, `coin_twinkle_period` 3.6 s, random offset per spawn) |
| Health cell | `health_pickup.tscn` | 10 | `level.heal(GameConfig.health_pickup_amount)` = +25, clamped to the ship's max health, green "+25" popup |
| Shield bubble | `shield_pickup.tscn` | 10 | `player.activate_shield(GameConfig.shield_duration)` = 8 s. Absorbs enemy shots, mine blasts and all contact: no health loss, no blink, no weapon tier loss, combo kept; each absorbed hit pops the ring, the shield keeps going. It is an offensive window: see "Shield rams" below. The UFO beam still drains at `shield_drain_factor` (0.5x). Ring blinks in the last 2 s; re-collecting refreshes to the full 8 s; it ends at game over and when the victory docking starts. HUD: cyan "SHIELD" + timer bar next to the combo |
| Missile upgrade | `missile_pickup.tscn` | 10 | `player.activate_missiles(GameConfig.missile_duration)` = 8 s of sidewinder missile pairs while firing (see "Missiles"); re-collecting refreshes to the full 8 s; it ends at game over and when the victory docking starts. Orange "MISSILES" popup; HUD: orange "MISSILES" + timer bar in the height row |
| Screen-clear bomb | `bomb_pickup.tscn` | 25 | Fires on pickup: "BOMB!", 0.25 s white flash, big shake; every ordinary obstacle on screen (fodder, scouts, mines, asteroids, minions) is killed through `Obstacle.bomb_kill()` (9999 damage: normal kill points, combo rises as usual, but asteroids do NOT split: `suppress_splits`). The heavy enemies are only damaged: the boss and every `Obstacle.bomb_resistant` obstacle (set in `blimp_obstacle.tscn` and `ufo_obstacle.tscn`: the zeppelin and the mini-boss UFO) take `GameConfig.bomb_boss_damage` (150) through the normal `take_damage()` path (hit flash, health bar; if that finishes one it dies normally: points, combo, zeppelin loot). A survivor carries on unchanged (UFO hover / ring / bolt, zeppelin guns and missile timers, the wave manager's mini-boss hold). "On screen" = position inside the viewport grown by 24 px, so an entering UFO or a zeppelin still above the top edge is untouched. Enemy projectiles on screen (group `enemy_projectile`, the zeppelin's missiles and the UFO's ring shots included) are removed |

Weights per zone (`ZoneDefinition.pickup_weight_energy / _health / _shield /
_bomb / _missile`, group "Pickup Weights"; relative, they need not sum to 100;
the share column is the missile upgrade's chance per pickup roll):

| Zone | Energy | Health | Shield | Bomb | Missile | Missile share |
|---|---|---|---|---|---|---|
| ground | 100 | 0 | 0 | 0 | 0 | 0% |
| atmosphere | 70 | 15 | 10 | 5 | 0 (the zeppelin drops one) | 0% |
| upper_atmosphere | 60 | 20 | 12 | 8 | 5 | 4.8% |
| space | 55 | 20 | 15 | 10 | 6 | 5.7% |
| orbit | 60 | 30 | 10 | 0 (no bombs in the boss fight) | 0 | 0% |

Shield rams (`main_level.gd` `_on_shielded_contact()`): while shielded,
ramming an ordinary obstacle destroys it (as any ram does) AND awards its kill
points through `award_kill_points()`, so the combo multiplier applies and
rises: 8 s of shield is a fun offensive window, not just a free pass. The
boss and the blimp survive contact as usual; each shielded contact hit (their
`contact_hit_interval`, 0.5 s) deals `GameConfig.shield_ram_damage` (40) to
them instead of hurting the player. A mine blast is simply absorbed.
While shielded the hit area is the shield circle (radius 126 local, ~101 px on
screen; `CollisionArea/ShieldShape`, `player.gd` `shield_hit_radius`): enemy
shots are absorbed, enemies rammed and pickups collected at the sphere edge,
the UFO beam catches the ship sooner, and no grazes count (`can_graze()`).

Coin value: a normal full run (autopilot, seed 4242) spawned 17 coins and
collected 15, so coins add about 75 points of ~8200 (they were worth 15
at 1 point each). The blimp's energy drop is a coin too.

Attract-mode demo: the autopilot chases energy, health, shield and missile
pickups but never a bomb (it steers around it), so the demo screen never empties.

Guarantees (`SpawnManager.roll_pickup_kind()`): at most one shield, one
bomb and one missile upgrade on screen at a time, and no health cell while the player is at full
health; a roll that breaks one becomes energy.

Drops (bypass the table and its limits, via
`SpawnManager.spawn_collectible_at(position, scene)`): the blimp drops one
energy + one health cell + one missile upgrade (`collectible_drops`,
`health_drops`, `missile_drops`); the boss drops
one health cell below itself when it enters phase 2 and phase 3
(`main_level.gd` `_on_boss_phase_changed`).

The pickup scenes and values live in `data/game_config.tres` (group
"Pickups": `energy_collectible_scene`, `health_pickup_scene`,
`shield_pickup_scene`, `bomb_pickup_scene`, `missile_pickup_scene`,
`health_pickup_amount`, `shield_duration`, `missile_duration`,
`shield_drain_factor`, `bomb_boss_damage`: the bomb's damage to the
mothership, the zeppelin and the mini-boss UFO); the SpawnManager copies the
scenes in `configure()`.

## Missiles

Three homing missile types, all pooled through the `ObjectPool` autoload
(never `queue_free()`d), timed by `_process()` accumulators (they freeze
while paused) and cheap: Polygon2D / one shader quad plus at most one small
CPUParticles2D trail each.

**Shootable enemy shots.** Player lasers (`projectile.gd`) and player
missiles also hit Area2Ds on physics layer value 32 (layer 6,
`SHOOTABLE_LAYER`; `projectile.gd` ORs it into its mask in `_ready()`, the
laser scenes keep mask 2) that are in group `shootable` and have a duck-typed
`take_damage(amount)` and `is_active`. The zeppelin missile and the seeker
orb are on layer 4 | 32 (enemy shot + shootable). Shot down, they pop (small
explosion) and award their points through `level.award_kill_points()`, i.e.
as a kill: the combo applies and rises. Both stay enemy projectiles for every
other rule (group `enemy_projectile`: the bomb's `clear()` removes them and
the autopilot dodges them; shield absorb at the bubble edge with the ripple;
no damage while blinking or dead; damage through `level.update_health()`,
which resets the combo, starts the blink and applies the optional tier loss;
grazes).

### Player missiles (temporary upgrade)

`player.gd` `activate_missiles(duration)`; missile `scenes/effects/player_missile.tscn`
/ `scripts/effects/player_missile.gd`. While active AND firing, a pair leaves
the two wing gun hardpoints (`LeftGunpoint` / `RightGunpoint`, at the ship's
`wing_gun_x/y` whatever the tier) every `missile_interval`, angled outward, on
top of the tier's shots. Ends on timeout, death, the victory landing
(`fly_to`), `reset_position()` and scene reload. HUD: `update_missiles()`.

| Knob | Where | Value |
|---|---|---|
| `missile_duration` | `data/game_config.tres` (Pickups) | 8.0 s (re-collect refreshes) |
| `missile_interval` | `player.gd` export | 0.55 s between pairs |
| `missile_launch_angle_degrees` | `player.gd` export | 20 deg outward from straight up |
| `launch_speed` / `max_speed` / `acceleration` | `player_missile.gd` | 380 -> 720 px/s at 700 px/s^2 |
| `turn_rate_degrees` | `player_missile.gd` | 260 deg/s |
| `damage` | `player_missile.gd` | 30 x the ship's `damage_scale` (set per launch by `player.gd`) |
| `boss_damage_scale` | `player_missile.gd` | 0.5 against the boss (the zeppelin takes full damage) |
| `lifetime` | `player_missile.gd` | 2.5 s |

Targeting at launch: the boss (once its fight started) or a mini-boss on
screen first, else the nearest active obstacle or shootable shot above the
ship; the second missile of a pair avoids the first one's target when that
dies to one hit. If the target dies or is reused, it retargets once to the
nearest; with no target it turns straight up. Hits go through
`take_damage()`, so kill points, combo, hit flash, health bars and loot work
as for lasers; impact = small explosion + hit spark (no shake).

Measured (casual bot, missiles kept active the whole fight): boss at tier 3
19.8 -> 10.3 s (with `boss_damage_scale` 1.0 it was 6.7 s, which trivialized
the fight), zeppelin at tier 2 15.5 -> 8.2 s. In normal play the upgrade
comes from the zeppelin's drop and rare upper atmosphere / space rolls, so it
mostly clears waves for 8 s; it can only reach the boss as a carry-over.

### Zeppelin missiles

`scenes/effects/enemy_missile.tscn` / `scripts/effects/enemy_missile.gd`,
fired by `blimp_obstacle.gd` from the two side pods (GunPoint1 / GunPoint3) in
addition to its guns. Each pair is telegraphed by `PodFlashLeft/Right` (star
flashes at the pods). Missiles fly at 230 px/s, home on the player at up to
110 deg/s for `homing_time`, then keep their heading (dodgeable).

| Knob | Where | Value |
|---|---|---|
| `missile_interval` | blimp (group "Blimp Missiles") | 4.5 s, launch to launch |
| `first_missile_delay` | blimp | 2.0 s after both pods are on screen |
| `missile_telegraph_time` | blimp | 0.35 s pod flash before each pair |
| `max_live_missiles` | blimp | 4 (a pair launches what fits; with no room it retries) |
| `missile_launch_angle` | blimp | 35 deg outward from straight down |
| `speed` / `damage` / `lifetime` | `enemy_missile.tscn` | 230 px/s / 20 / 6 s |
| `turn_rate_degrees` / `homing_time` | `enemy_missile.gd` | 110 deg/s / 2.2 s |
| `max_health` | `enemy_missile.gd` | 20 (2 laser hits at 10, 1 player missile) |
| `shot_down_points` | `enemy_missile.gd` | 5 (as a kill: combo applies) |
| `missile_drops` | blimp | 1 missile upgrade on death (plus the energy and health cell) |

Measured (casual bot, tier 2, zeppelin alone, 10 seeded runs), before ->
after: kill time 14.4 -> 15.5 s (shots spent on missiles), health lost 10 ->
14, survival 10/10; per fight 3.8 missiles shot down vs 0.3 reaching the
player.

### Seeker orbs (Alien Mothership)

`scenes/effects/alien_seeker.tscn` / `scripts/effects/alien_seeker.gd`
(extends the enemy missile): a glowing magenta orb with a pulsing green core
(procedural `shaders/alien_seeker.gdshader` on a 64x64 ColorRect, no
texture). It homes loosely on the player for its whole flight on a hidden
base point and is drawn `weave_amplitude * sin(2 pi weave_frequency t +
phase)` px to the side of it (random phase per orb), so it snakes. Shot down:
pop, +10 (as a kill), no burst. Reaching the player: 20 damage by the
projectile rules. When `fuse_time` runs out it bursts into a ring of
`burst_count` slow bullets (`burst_scene` = `enemy_projectile_3.tscn`, speed
and lifetime set per spawn and restored when the bullet is pooled) with an
energy flash; in its last `tell_time` it blinks fast as the tell.

| Knob | Where | Value |
|---|---|---|
| `speed` / `turn_rate_degrees` | `alien_seeker.tscn` | 170 px/s / 90 deg/s |
| `weave_amplitude` / `weave_frequency` | `alien_seeker.gd` | 45 px / 1.2 Hz |
| `max_health` / `shot_down_points` / `damage` | `alien_seeker.tscn` | 20 (2 laser hits) / 10 / 20 |
| `fuse_time` / `tell_time` / `tell_blink_rate` | `alien_seeker.gd` | 4.5 s / 1.0 s / 14 toggles/s |
| `burst_count` / `burst_speed` / `burst_lifetime` | `alien_seeker.gd` | 6 / 160 px/s / 6 s |
| Boss cadence / cap | `boss_alien.gd` `PHASES`, `max_orbs` | phase 2: 2 every 5 s; phase 3: 3 every 4 s; max 5 live |
