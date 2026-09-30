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

1. **Slot**: wait until fewer than `GameConfig.max_formations_on_screen` (3)
   formations are alive. A scene_override group counts as one formation.
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
cleared. A `scene_override` group released `ON_CLEAR` (the blimp) still holds
the wave: it is a deliberate mini-boss beat. After the last wave
the zone loops from the first wave. `one_shot` groups that already spawned
during this visit are skipped. Changing zone restarts the sequence at wave 0
with ramp 0. Formations already flying keep flying. Zones without waves (the
orbit/boss zone) spawn nothing.

### Difficulty ramp (adds speed, never bodies)

`ramp level = int(time in zone / ramp_interval_seconds)` (25 s). Per level:

- path and descend speeds × `ramp_speed_multiplier` (1.1, capped at
  `max_speed_multiplier` 1.6). HOLD_THEN_DESCEND hover time is divided by the
  same factor.
- beats, delays, completion delays and the telegraph × `ramp_beat_multiplier`
  (0.9, floored at `min_beat_multiplier` 0.5).

Counts never change. Self-moving singles (blimp, UFO) keep their own speeds.
The HUD threat indicator shows the ramp level (`WaveManager.get_ramp_level()`).

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
| VOLLEY | Every `fire_interval`, every live on-screen member with `can_shoot` fires at once |
| RIPPLE | Every `fire_interval`, members fire one after another in index order, 0.12 s apart |
| INDIVIDUAL | Members use the old per-frame random shooting (`Obstacle._process_shooting`) |

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

`waves` (the sequence) and `formation_settings`. `obstacle_scenes` and the
movement pattern weights are only used by the legacy `spawn_obstacle()` and by
boss minions. Ramp: `ramp_interval_seconds` (25), `ramp_speed_multiplier` (1.1),
`max_speed_multiplier` (1.6), `ramp_beat_multiplier` (0.9),
`min_beat_multiplier` (0.5).

### FormationSettings (`scripts/data/formation_settings.gd`)

`default_spread`, plus the swarm fields `swarm_radius`, `swarm_sine_amplitude`,
`swarm_sine_frequency` (sway around the path), and `swarm_jitter_*`.

### GameConfig caps

`max_active_obstacles = 60`, `max_formations_on_screen = 3`,
`telegraph_seconds = 0.5`.

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
   AFTER_DELAY group adds a formation to the screen at once, and the cap of 3
   still applies.
5. For a symmetric pincer, add two groups with the same path. Set the first to
   `mirror_allowed = false` and AFTER_DELAY 0. Set the second to
   `force_mirror = true`.
6. A new path needs a new `EntryPath` resource in `data/paths/`. Author it
   left-handed in normalized coordinates, start it off screen (y < 0 or x < 0),
   and keep the on-screen part inside x 0.1..0.9 so formation offsets don't
   clip the sides.
7. The first wave of a zone should be the simplest: one formation with no fire.

## Authored waves

Times are bot loop times at ramp 0 (headless harness, invulnerable sweeping
bot, tier-2 auto-fire, `--fixed-fps 60`); they vary by a few seconds between
runs (mirror rolls, physics). The bot usually kills the UFO within ~2 s; a UFO
left alive lives ~22 s, which no longer holds its wave (see above).
C = `completion_delay`; beat = `beat_after`. Groups are ON_CLEAR unless an
AFTER_DELAY value is given.

### Ground (spread 90; loop ≈ 14 s)

| Wave | Groups | C |
|---|---|---|
| 1 Welcome | 3 × balloon_1 LINE `top_straight` (spread 110), NONE, beat 0.4 | 0.5 |
| 2 Planes | 4 × plane_1 V_SHAPE `swoop_left` (mirror), NONE, beat 0.4 | 0.5 |
| 3 Swarm | 6 × drone SWARM `side_sweep_left` (mirror), NONE, beat 0.6 | 1.0 |

### Atmosphere (spread 100; first loop ≈ 32 s with the blimp, then ≈ 28 s)

| Wave | Groups | C |
|---|---|---|
| 1 Jet Swoop | 5 × jet_1 V `swoop_left` RIPPLE 2.0, AFTER_DELAY 1.5 → 3 × balloon_5 LINE `top_straight` (spread 120), NONE, beat 1.2 | 1.5 |
| 2 Pincer | 3 × jet_2 DIAGONAL `pincer_left` (no mirror) VOLLEY 2.5, AFTER_DELAY 0 → 3 × jet_2 DIAGONAL `pincer_left` force_mirror VOLLEY 2.5, beat 1.2 | 1.5 |
| 3 Drone Loop | 7 × drone SWARM `loop_left`, AFTER_DELAY 2.0 → 4 × plane_1 V `swoop_left`, beat 1.2 | 1.5 |
| 4 Blimp | 1 × blimp (scene_override, enters at top center), one_shot, beat 1.0 | 1.0 |
| 5 Turrets | 4 × balloon_3 LINE `hover_top` hold 6 s (spread 120) VOLLEY 2.0, beat 1.2 | 2.0 |

### Upper atmosphere (spread 100; loop ≈ 47-58 s)

| Wave | Groups | C |
|---|---|---|
| 1 Jet Loop | 6 × jet_1 DIAGONAL `loop_left` (spread 110) RIPPLE 1.8, beat 1.2 | 1.5 |
| 2 Meteor Dive | 5 × meteor_1 LINE `dive_center` (spread 110), AFTER_DELAY 1.2 → 5 × meteor_2 LINE `dive_center` force_mirror, beat 1.2 | 1.5 |
| 3 Saucer Escort | 1 × UFO (scene_override, does not hold the wave), AFTER_DELAY 1.0 → 4 × jet_2 V `pincer_left` VOLLEY 2.2, beat 1.2 | 1.5 |
| 4 Satellite Grid | 4 × satellite_turret SQUARE `hover_top` hold 5 s (spread 120) VOLLEY 1.8, beat 1.2 | 1.5 |
| 5 Asteroids | 3 × asteroid LINE `top_straight` (spread 200), NONE, beat 1.2 | 1.5 |
| 6 Swarm Strike | 6 × drone SWARM `swoop_left`, AFTER_DELAY 1.0 → 3 × jet_8 LINE `dive_center` (spread 100) RIPPLE 1.2, beat 1.2 | 1.5 |
| 7 Crossfire | 5 × jet_9 WAVE `side_sweep_left` (spread 70) RIPPLE 1.6, AFTER_DELAY 1.5 → 5 × jet_9 WAVE `side_sweep_left` force_mirror RIPPLE 1.6, beat 1.2 | 2.0 |

### Space (spread 110; loop ≈ 34-43 s)

| Wave | Groups | C |
|---|---|---|
| 1 Alien Swoop | 5 × alien V `swoop_left` VOLLEY 2.0, beat 0.8 | 1.0 |
| 2 Minefield | 5 × mine LINE `top_straight` (spread 130), NONE, AFTER_DELAY 0.5 → 3 × satellite_3 DIAGONAL `side_sweep_left` (spread 90), AFTER_DELAY 1.5 → 3 × satellite_4 DIAGONAL `side_sweep_left` force_mirror, beat 0.8 | 1.0 |
| 3 Saucer Rocks | 1 × UFO (scene_override, does not hold the wave), AFTER_DELAY 1.0 → 2 × asteroid LINE `dive_center` (spread 160), AFTER_DELAY 2.5 → 2 × asteroid LINE `dive_center` force_mirror, beat 0.8 | 1.0 |
| 4 Alien Ring | 8 × alien CIRCLE `hover_top` hold 6 s (spread 110) RIPPLE 1.5, beat 0.8 | 1.0 |
| 5 Jet Pincer | 3 × jet_8 V `pincer_left` (no mirror) VOLLEY 2.0, AFTER_DELAY 0 → 3 × jet_9 V `pincer_left` force_mirror VOLLEY 2.0, AFTER_DELAY 1.5 → 8 × drone SWARM `loop_left` (380 px/s), beat 0.8 | 1.5 |

Orbit has no waves: the boss fight plays alone.
