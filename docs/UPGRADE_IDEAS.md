# Soms In Space: upgrade ideas and asset wishlist

Written 2026-09-30 after the refresh phases 1-4 (commits b903dae, 91e2a28, 119a6c9).
Everything here is sized against what the project already uses, so each item drops
into the existing obstacle, collectible, or HUD systems without new plumbing.

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

| # | Feature it unlocks | What to make | Spec |
|---|---|---|---|
| 1 | Real boss instead of a tinted alien | Mothership sheet: idle, attack, hurt, death | Grid sheet, 6 to 8 frames per animation, ~512x384 per frame, facing down, transparent |
| 2 | "Choose your SoM" ship select on the main menu, each ship with its own speed, fire rate, and health | 3 ship sprites (e.g. phyCORE-AM62x, i.MX 8M, i.MX 93) plus a small name badge each | 1024x1536 each, facing up, engine at bottom center, same silhouette scale as the current ship |
| 3 | Zone parallax backgrounds so the climb feels like travel | Ground skyline or launch site, aurora band for upper atmosphere, Earth horizon curve for space, a space station for orbit | 720 px wide strips, horizontally tileable where they scroll, transparent above the horizon, 1 to 3 layers per zone |
| 4 | Victory moment: dock with a PHYTEC station | Station sprite and a short docking clamp animation | ~800x600 station, 4 to 6 frame clamp sheet |
| 5 | New enemy types. Ground: drone swarm that flocks. Atmosphere: blimp mini-boss with turrets. Space: UFO with a tractor beam, splitting asteroid, blinking space mine | One PNG per enemy, sheets for the UFO beam and mine blink; asteroid in 3 sizes | 256 to 512 px, facing down; beam as a vertical strip ~64x400; mine 2 to 4 blink frames |
| 6 | Damage states on enemies and the player | Smoke or crack overlay frames | 2 to 3 frames per enemy family, same canvas size as the enemy |
| 7 | New pickups: shield bubble, screen-clear bomb, health cell; distinct icons for weapon tiers 2 and 3 | 5 pickup icons and a shield ring sprite | Icons 256x256 in a consistent style; shield ring ~300x300 with soft alpha edge |
| 8 | HUD polish: pause, heart, threat skull, three weapon tier icons | 6 icons | 128x128, one color plus alpha so code can tint them |
| 9 | Menu title | Game logo | ~600x200 transparent, plus a version with the PHYTEC mark for the kiosk |
| 10 | Sound and music | Boss loop, victory jingle, game-over sting, menu blip, power-up, player hit, boss roar and hit, warning klaxon, tier-3 shot | OGG for loops, MP3 or OGG for one-shots, 1 to 3 s each |

Items 1 through 4 change how the game feels at a booth. Item 2 turns the demo into
a PHYTEC product story: pick your module, see its stats, fly it.

## Fun that needs no new art (code only)

- Screen shake and hit-stop on kills
- Floating score popups
- Combo multiplier for kill streaks
- Near-miss bonus points for grazing bullets
- Chained explosions when enemies die close together
- Richer enemy bullet patterns (rings, spirals, aimed bursts)
- More wave and formation definitions per zone (all data in `data/zones/*.tres`)
- Ship banking when moving sideways
- Attract-mode demo that plays itself on the main menu until someone touches the screen

## Still to verify on the device

- Touch feel, pause button ergonomics, onscreen keyboard on the results screen
- How the boss tint shader, spread laser, and threat pips look under opengl3_es
- Frame rate with up to 150 active obstacles (`max_active_obstacles` in `data/game_config.tres`)
- Boss fairness: volley size and spread are exports on `scripts/obstacles/boss_alien.gd`
