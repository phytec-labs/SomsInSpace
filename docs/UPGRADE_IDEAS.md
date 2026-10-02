# Soms In Space: upgrade ideas and asset wishlist

Written 2026-09-30 after the refresh phases 1-4 (commits b903dae, 91e2a28, 119a6c9).
Everything here is sized against what the project already uses, so each item drops
into the existing obstacle, collectible, or HUD systems without new plumbing.

## Done

Built since this list was written (code complete; most still run on stand-in
art, see `docs/ART_SWAP_TRACKER.md`), so the tables below are the remaining
backlog:

- Ship select ("Choose your SoM", three ships with their own stats): wishlist #2, code
  done, ship art still needed
- New enemies: drone swarm, blimp mini-boss, UFO with tractor beam, splitting asteroid,
  space mine: wishlist #5, code done; splitting asteroid art wired (two tumbling large
  rocks, 8 medium chunks, 18 small shards), see the tracker for the rest
- Victory docking with a PHYTEC station: wishlist #4, done (station art wired; the ship
  lands on its central pad: shrink-to-pad flight, green touchdown ring, flash, DOCKED)
- Pickups: health cell, shield bubble, screen-clear bomb, weighted per zone: wishlist #7,
  code done, shield and bomb icons and the shield bubble wired (health and weapon tier
  icons still open)
- Juice: screen shake, floating score popups, combo multiplier, near-miss graze bonus
- Wave rework: choreographed formations, spawn telegraphs, richer bullet patterns (fire
  patterns), more waves per zone
- Attract-mode demo that plays itself from the main menu until someone touches the screen
- Missiles: a temporary sidewinder missile upgrade for the player (zeppelin drop + rare
  pickups), homing zeppelin missiles and the Alien Mothership's weaving seeker orbs
  (shootable, burst into a bullet ring); the mothership summons minions in every
  phase. Code done; the sidewinder art is wired in two liveries: blue/white on the player
  missile and the pickup icon (inside the code-drawn tile), red/white (untinted) on the
  zeppelin's missile (the orb is procedural)
- Animated bomb pickup icon (6-frame sheet) wired
- UFO weapons: the mini-boss saucer fires a telegraphed pulse ring while it hovers and
  charges a bolt down its beam on a player who stays caught; scout saucers (60% size,
  three-shot fan volleys) replaced the satellites in space, drawn with the teal second-colour
  UFO render (`ufo_2`)
- Energy coin: worth 5 points (flat), gold "+5" popup and a quick coin pop on collect,
  drawn by a procedural spinning-coin shader (embossed microchip emblem; star and
  lightning bolt selectable) instead of the old pixel sprite

## How art plugs in today

- **Enemies** are one transparent PNG each, drawn large and scaled down in the scene.
  Current sources run 400 to 650 px on a side and show at roughly 50 to 90 px on
  screen. Any size in that range works. Enemies face down toward the player.
- **Animated enemies** use a uniform grid sheet. The alien sheet (`sprites/alien_1.png`)
  is 5 columns by 4 rows of 214x175 frames at 12 fps with an `idle` loop and a
  one-shot `attack`. That layout is the template for new sheets.
- **Player ship** (`sprites/player_ship_body2.png`) is 1024x1536, facing up, engine at
  bottom center, shown at 10 percent scale.
- **Projectiles** are single frames around 120x120 to 240x140 (`sprites/Laser Sprites/`).
- **Explosions** are a 12-frame strip of 96x96 (`sprites/Explosion1.png`) used as a
  particle texture.
- **Audio** is MP3 under `audio/`. One music track and five effects. OGG also works and
  loops more cleanly for music.
- Solid backgrounds cannot be used. The archived Midjourney sheets in `art_archive/`
  are on white or beige, so anything new needs real alpha.
- Archived assets can be restored with `git mv` plus
  `git checkout 3f1cb1e -- '<path>.import'` to get the original 4.4 import file back.

## Wishlist, ordered by fun per effort

| # | Feature it unlocks | What to make | Spec | Status |
|---|---|---|---|---|
| 1 | Real boss instead of a tinted alien | Mothership sheet: idle, attack, hurt, death | Grid sheet, 6 to 8 frames per animation, ~512x384 per frame, facing down, transparent | open (boss uses the tinted alien) |
| 2 | "Choose your SoM" ship select on the main menu, each ship with its own speed, fire rate, and health | 3 ship sprites (e.g. phyCORE-AM62x, i.MX 8M, i.MX 93) plus a small name badge each | 1024x1536 each, facing up, engine at bottom center, same silhouette scale as the current ship | code done, art needed |
| 3 | Zone parallax backgrounds so the climb feels like travel | Ground skyline or launch site, aurora band for upper atmosphere, Earth horizon curve for space, a space station for orbit | 720 px wide strips, horizontally tileable where they scroll, transparent above the horizon, 1 to 3 layers per zone | open |
| 4 | Victory moment: dock with a PHYTEC station | Station sprite (landing pad; clamps dropped for a landing), optional animated pad lights | `space_station_1.png` delivered; optional 2 to 4 frame pad-light loop | done (art wired) |
| 5 | New enemy types. Ground: drone swarm that flocks. Atmosphere: blimp mini-boss with turrets. Space: UFO with a tractor beam, splitting asteroid, blinking space mine | One PNG per enemy, sheets for the UFO beam and mine blink; asteroid in 3 sizes (delivered and wired: two 8-frame large tumbles, 8 medium chunks, 18 small shards) | 256 to 512 px, facing down; beam as a vertical strip ~64x400; mine 2 to 4 blink frames | code done, art needed |
| 6 | Damage states on enemies and the player | Smoke or crack overlay frames | 2 to 3 frames per enemy family, same canvas size as the enemy | open |
| 7 | New pickups: shield bubble, screen-clear bomb, health cell, missile upgrade; distinct icons for weapon tiers 2 and 3 | 6 pickup icons and a shield ring sprite | Icons 256x256 in a consistent style; shield ring ~300x300 with soft alpha edge | code done for shield / bomb / health / missiles; shield, health and bomb (animated sheets) wired; missile icon and weapon tier icons open |
| 8 | HUD polish: pause, heart, threat skull, three weapon tier icons | 6 icons | 128x128, one color plus alpha so code can tint them | open |
| 9 | Menu title | Game logo | ~600x200 transparent, plus a version with the PHYTEC mark for the kiosk | open |
| 10 | Sound and music | Boss loop, victory jingle, game-over sting, menu blip, power-up, player hit, boss roar and hit, warning klaxon, tier-3 shot | OGG for loops, MP3 or OGG for one-shots, 1 to 3 s each | open |

Items 1 through 4 change how the game feels at a booth. Item 2 turns the demo into
a PHYTEC product story: pick your module, see its stats, fly it.

## Fun that needs no new art (code only)

- Screen shake on kills (done); hit-stop (open)
- Floating score popups (done)
- Combo multiplier for kill streaks (done)
- Near-miss bonus points for grazing bullets (done)
- Chained explosions when enemies die close together
- Richer enemy bullet patterns (rings, spirals, aimed bursts) (partly done: volley / ripple fire patterns, boss volleys, homing zeppelin missiles, seeker orbs bursting into rings, UFO pulse rings, scout fans)
- More wave and formation definitions per zone (all data in `data/zones/*.tres`) (done: wave rework)
- Ship banking when moving sideways
- Attract-mode demo that plays itself on the main menu until someone touches the screen (done)

## Still to verify on the device

- Touch feel, pause button ergonomics, onscreen keyboard on the results screen
- How the boss tint shader, spread laser, and threat pips look under opengl3_es
- Frame rate with up to 150 active obstacles (`max_active_obstacles` in `data/game_config.tres`)
- Boss fairness: volley size and spread are exports on `scripts/obstacles/boss_alien.gd`
