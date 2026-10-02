# Changelog

All notable changes to Soms In Space are listed here, newest release first.

## v2.0.0 (2026-10-02)

Changes since [v1.0.0-RC4.1](https://github.com/phytec-labs/SomsInSpace/releases/tag/v1.0.0-RC4.1)
(commit `3f1cb1e`): 30 commits,
[full diff](https://github.com/phytec-labs/SomsInSpace/compare/v1.0.0-RC4.1...v2.0.0).

A run is now a three-minute climb with an ending: pick a ship, fight through
five zones of choreographed waves, beat the Alien Mothership and land on the
station. Between players the kiosk plays itself.

### Upgrade notes

- **Godot 4.7.1 is required** (was 4.4). The arm64 export templates must match
  exactly. See [BUILD.md](BUILD.md).
- **High scores reset.** The save file is now versioned, and saves from v1.x
  are discarded on first start because scoring changed.
- **Building no longer needs the editor.** `tools/build.sh` checks the Godot
  version, can install the templates, and exports `build/Soms-In-Space.arm64`.

### The run

- New fifth zone, Orbit, with the **Alien Mothership** boss: animated
  mothership art, three phases by health, aimed shots, fan volleys, summoned
  minions, and weaving seeker orbs that burst into a bullet ring unless shot
  down. A boss health bar sits at the top of the screen.
- **Victory ending.** After the boss, the ship lands on a space station pad,
  then the results screen shows a health-based bonus. There is no endless mode.
- Pacing retuned so a full run takes about three minutes. Height freezes
  during the boss fight.
- **Choose your SoM** ship select before launch, with three ships that differ
  in health, speed, fire rate and damage: TI SoM - AM62Px (balanced),
  i.MX SoM - i.MX95 (heavy), Qualcomm SoM - IQ2390 (light).

### Enemies and waves

- Waves are authored patterns a player can learn: one enemy type per
  formation, entering along fixed paths (swoops, loops, pincers, side sweeps,
  dives), with left/right mirroring as the only variation. A marker shows
  where each formation will enter. Formations fire as volleys or ripples.
- Difficulty rises through enemy speed and health per zone instead of filling
  the screen. At most three formations are on screen (four in the atmosphere
  zones) and at most 60 enemies.
- New enemies: drone swarms, proximity mines, splitting asteroids (large,
  medium chunks, small shards), and scout saucers that fire three-shot fans.
- Two mini-bosses:
  - **Zeppelin** (atmosphere): arrives after the weapon upgrade is collected,
    fires from three gun points and launches homing missiles that can be shot
    down.
  - **UFO** (upper atmosphere and space): pulls the ship in with a tractor
    beam that drains health, fires a ring of bullets every three seconds, and
    charges a bolt down the beam if the ship stays caught.
- Enemies react to hits with a white flash, a scale punch, sparks and a tick
  sound. Tougher enemies show a small health bar once damaged.
- Enemies are drawn in their true colors with a rim light on the dark skies
  of the upper atmosphere, space and orbit, so they stay readable.

### Weapons and pickups

- Three weapon tiers: Laser, Twin Laser and Spread Laser. Upgrades drop in the
  atmosphere and upper atmosphere.
- **Missiles**: a pickup that fires homing missile pairs for eight seconds.
  The zeppelin always drops one.
- **Shield**: an eight-second bubble that absorbs hits and destroys ordinary
  enemies on contact. While it is up, the ship's hit area is the bubble.
- **Bomb**: destroys small and medium enemies on screen and clears enemy
  shots. The zeppelin, the mini-boss UFO and the mothership take 150 damage
  instead.
- **Health cell**: restores 25 health.
- **Coins** are worth 5 points (was 1) and show a "+5" when collected.

### Scoring and feel

- Combo multiplier up to x4 for kill streaks, shown in the HUD.
- Graze bonus for near misses with enemy shots.
- Floating score popups, screen shake, and a threat indicator in the HUD.

### Kiosk

- **Attract mode**: after 20 seconds idle on the main menu the game plays
  itself under a "DEMO / TOUCH TO PLAY" overlay. Any touch exits to ship
  select, and demo runs never record a score.
- Results, pause and credits screens return to the main menu when left idle.
- Ship select resets to the first ship each time it opens.
- Pause menu with an on-screen button (and Escape).
- Touches on the HUD and background now reach the ship.

### Art

- New art for the three player ships, jets, drones, mines, both UFOs, the
  zeppelin, asteroids, the mothership, the space station, missiles, and the
  shield, health and bomb pickups.
- Shader-drawn effects that need no art: the player shield, the UFO tractor
  beam, the mothership's seeker orbs, and a spinning gold coin.
- Full-size masters are kept in `art_archive/masters/`. `tools/resize_art.gd`
  produces the downscaled game textures, with mipmaps. Texture memory dropped
  from about 93 MiB to 83 MiB when the pipeline was introduced.

### Fixes

- Enemies reused from the pool no longer keep stale health, rotation or
  shooting state from their previous life.
- Enemy shots no longer damage the player while the ship is blinking after a
  hit, or after it is destroyed.
- Wave delays of zero seconds no longer raise engine errors.
- The alien attack animation no longer loops.
- The weapon pickup awards its points and falls at the intended speed.
- The credits panel is centered again.

### Under the hood

- Zone tuning, waves, formations, entry paths, ships and pickup odds are data
  resources under `data/`, editable without touching scripts.
- One shared object pool for enemies, shots, explosions, pickups and popups.
- 111 unreferenced assets moved out of the project into `art_archive/`.
- New documentation: [BUILD.md](BUILD.md), `docs/WAVE_DESIGN.md` (waves,
  difficulty knobs, time-to-kill tables), `docs/ART_SWAP_TRACKER.md` (which
  art is final and which is a stand-in) and `docs/UPGRADE_IDEAS.md`.

### Known gaps

- Stand-ins remain for the spawn marker, the hit spark and the hit sound.
- The mothership has an idle animation only. Attack, hurt and death frames
  are still open, and its minions still use the older pixel art.
- No new music or sound effects in this release.

## v1.0.0-RC4.1 (2025-08-21)

Last release candidate of the original game.
