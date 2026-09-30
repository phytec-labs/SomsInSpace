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

`waves` (the sequence) and `formation_settings`. `obstacle_scenes` and the
movement pattern weights are only used by the legacy `spawn_obstacle()` and by
boss minions. Ramp: `ramp_interval_seconds` (25), `ramp_speed_multiplier` (1.1),
`max_speed_multiplier` (1.6), `ramp_beat_multiplier` (0.9),
`min_beat_multiplier` (0.5).

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
medium / small), UFO 40, blimp 160 (320 in the atmosphere, its only zone).

### FormationSettings (`scripts/data/formation_settings.gd`)

`default_spread`, plus the swarm fields `swarm_radius`, `swarm_sine_amplitude`,
`swarm_sine_frequency` (sway around the path), and `swarm_jitter_*`.

### GameConfig caps

`max_active_obstacles = 60`, `max_formations_on_screen = 3`,
`telegraph_seconds = 0.5`.

## Difficulty knobs

The values play-testing usually touches, and where they live:

| Knob | Where | Current | Effect |
|---|---|---|---|
| `enemy_health_multiplier` | each `data/zones/<zone>.tres` | ground 1.0, atmosphere 2.0, upper_atmosphere 2.5, space 3.0, orbit 1.0 | Hits to kill every non-boss enemy in the zone (table above) |
| Boss health | `scenes/obstacles/boss_alien.tscn` `health` | 750 | Fight length; phases change at 2/3 and 1/3 of it automatically (~16.5 s with the sweeping tier-2 bot) |
| Blimp health | `scenes/obstacles/blimp_obstacle.tscn` `health` | 160 (x 2.0 in atmosphere = 320) | Mini-boss length (~2 s of sustained tier-2 fire) |
| `first_fire_delay` | each `WaveGroup` | 0.6 s | Formation's first volley / ripple after it appears on screen |
| `fire_interval` | each `WaveGroup` | 1.2-2.5 s | Time between formation volleys / ripples |
| `first_shot_delay` | `Obstacle` export (per scene) | 0.5 s (blimp 0.8 s) | Individual shooters' first shot after spawning (only once on screen) |
| Ramp fields | each zone, "Difficulty Ramp" | 25 s, x1.1 (max 1.6), x0.9 (min 0.5) | How fast a zone speeds up while the player stays in it |
| `max_active_obstacles` | `data/game_config.tres` | 60 | Hard cap on live obstacles (safety valve) |
| `max_formations_on_screen` | `data/game_config.tres` | 3 | How many formations may overlap |

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
runs (mirror rolls, physics). They were measured before the zone health
multipliers; loops past the ground are now somewhat longer. The bot usually kills the UFO within ~2 s; a UFO
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
