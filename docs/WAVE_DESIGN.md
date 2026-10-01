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
with `can_shoot`, a `GunPoint1` and aimed shots).
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
medium / small), UFO 80 (200 in upper_atmosphere, 240 in space), blimp 270
(540 in the atmosphere, its only zone).

Big targets, balanced ship, sustained fire (headless, ship tracking the
target from 250-800 px below; seconds from the first hit to the kill):

| Target | Health | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|---|
| Blimp (atmosphere) | 540 (was 320) | ~10.8 s (54 hits) | ~4.0-4.4 s (was ~2.7-3.3 s) | ~3.3-4.1 s |
| UFO (upper_atmosphere) | 200 (was 100) | | ~2.2-2.4 s median (was ~1.2 s) | ~1.7-2.3 s (was ~0.6-0.8 s) |
| UFO (space) | 240 (was 120) | | ~2.5 s (was ~1.1-1.3 s) | ~1.9-2.9 s (was ~0.9-1.1 s) |

The Player node is scaled 0.8 in the level, so the balanced ship's wing guns
sit at about +-30 px on screen. The blimp's hull (capsule radius 40, ~94 px
wide sprite) takes all three tier-2 shots while the ship is within about
+-15 px of its center (2 per volley at +-20 px and beyond; the earlier
radius-30 hull only within about +-6 px). The tier-3 angled shots mostly
miss it, so tier 3 is only a little faster. The UFO is 200 px wide, so all
three tier-2 shots land; its sideways patrol and the ~1.5 s shot travel time
cost some hits. Either way the UFO dies well inside its 12 s hover.

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
| Boss health | `scenes/obstacles/boss_alien.tscn` `health` | 750 | Fight length; phases change at 2/3 and 1/3 of it automatically (~16.5 s with the sweeping tier-2 bot) |
| Blimp health | `scenes/obstacles/blimp_obstacle.tscn` `health` | 270 (x 2.0 in atmosphere = 540) | Mini-boss length (~4.0-4.4 s of sustained tier-2 fire, ~10-12 s for the casual bot) |
| UFO health | `scenes/obstacles/ufo_obstacle.tscn` `health` | 80 (x 2.5 = 200 upper_atmosphere, x 3.0 = 240 space) | ~2.3 s of sustained tier-2 fire; must die inside its 12 s hover |
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
(see the timeline below). The bot usually kills the UFO within a few seconds;
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

### Space (spread 110; loop ≈ 46-51 s)

| Wave | Groups | C |
|---|---|---|
| 1 Alien Swoop | 5 × alien V `swoop_left` VOLLEY 2.0, beat 0.8 | 1.0 |
| 2 Minefield | 5 × mine LINE `top_straight` (spread 130), NONE, AFTER_DELAY 0.5 → 3 × satellite_3 DIAGONAL `side_sweep_left` (spread 90), AFTER_DELAY 1.5 → 3 × satellite_4 DIAGONAL `side_sweep_left` force_mirror, beat 0.8 | 1.0 |
| 3 Saucer Rocks | 1 × UFO (scene_override, does not hold the wave), AFTER_DELAY 1.0 → 2 × asteroid LINE `dive_center` (spread 160), AFTER_DELAY 2.5 → 2 × asteroid LINE `dive_center` force_mirror, beat 0.8 | 1.0 |
| 4 Alien Ring | 8 × alien CIRCLE `hover_top` hold 6 s (spread 110) RIPPLE 1.5, beat 0.8 | 1.0 |
| 5 Jet Pincer | 3 × jet_8 V `pincer_left` (no mirror) VOLLEY 2.0, AFTER_DELAY 0 → 3 × jet_9 V `pincer_left` force_mirror VOLLEY 2.0, AFTER_DELAY 1.5 → 8 × drone SWARM `loop_left` (380 px/s), beat 0.8 | 1.5 |

Orbit has no waves: the boss fight plays alone.

## Pickups

Collectibles are not part of the wave data: the SpawnManager's collectible
timer (base 5 s x the zone's `collectible_time_scale`, spawn chance 0.7 x
`collectible_chance_scale`) spawns one pickup at a random x above the screen,
and `spawn_collectible()` rolls which one from the zone's pickup table.

| Pickup | Scene | Points | Effect |
|---|---|---|---|
| Energy | `energy_collectible_1.tscn` | 1 | Points only |
| Health cell | `health_pickup.tscn` | 10 | `level.heal(GameConfig.health_pickup_amount)` = +25, clamped to the ship's max health, green "+25" popup |
| Shield bubble | `shield_pickup.tscn` | 10 | `player.activate_shield(GameConfig.shield_duration)` = 8 s. Absorbs enemy shots, mine blasts and all contact: no health loss, no blink, no weapon tier loss, combo kept; each absorbed hit pops the ring, the shield keeps going. It is an offensive window: see "Shield rams" below. The UFO beam still drains at `shield_drain_factor` (0.5x). Ring blinks in the last 2 s; re-collecting refreshes to the full 8 s; it ends at game over and when the victory docking starts. HUD: cyan "SHIELD" + timer bar next to the combo |
| Screen-clear bomb | `bomb_pickup.tscn` | 25 | Fires on pickup: "BOMB!", 0.25 s white flash, big shake; every active non-boss obstacle on screen (incl. blimp, UFO, mines, minions) is killed through `Obstacle.bomb_kill()` (9999 damage: normal kill points, combo rises as usual, blimp loot drops, but asteroids do NOT split: `suppress_splits`), the boss takes `GameConfig.bomb_boss_damage` (150), enemy projectiles on screen (group `enemy_projectile`) are removed |

Weights per zone (`ZoneDefinition.pickup_weight_energy / _health / _shield /
_bomb`, group "Pickup Weights"; relative, they need not sum to 100):

| Zone | Energy | Health | Shield | Bomb |
|---|---|---|---|---|
| ground | 100 | 0 | 0 | 0 |
| atmosphere | 70 | 15 | 10 | 5 |
| upper_atmosphere | 60 | 20 | 12 | 8 |
| space | 55 | 20 | 15 | 10 |
| orbit | 60 | 30 | 10 | 0 (no bombs in the boss fight) |

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

Attract-mode demo: the autopilot chases energy, health and shield pickups
but never a bomb (it steers around it), so the demo screen never empties.

Guarantees (`SpawnManager.roll_pickup_kind()`): at most one shield and one
bomb on screen at a time, and no health cell while the player is at full
health; a roll that breaks one becomes energy.

Drops (bypass the table and its limits, via
`SpawnManager.spawn_collectible_at(position, scene)`): the blimp drops one
energy + one health cell (`collectible_drops`, `health_drops`); the boss drops
one health cell below itself when it enters phase 2 and phase 3
(`main_level.gd` `_on_boss_phase_changed`).

The pickup scenes and values live in `data/game_config.tres` (group
"Pickups": `energy_collectible_scene`, `health_pickup_scene`,
`shield_pickup_scene`, `bomb_pickup_scene`, `health_pickup_amount`,
`shield_duration`, `shield_drain_factor`, `bomb_boss_damage`); the
SpawnManager copies the scenes in `configure()`.
