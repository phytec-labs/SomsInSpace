# Building Soms In Space

The game is exported as a single Linux **arm64** executable (the `.pck` is
embedded) for the phyBOARD LYRA AM62x running Weston. The build runs on a
Linux x86_64 PC; nothing is compiled, Godot just packs the project into its
prebuilt arm64 export template.

```sh
tools/build.sh --install-templates
```

That is the whole build. The rest of this page explains what it needs and does.

## Prerequisites

- **Godot 4.7.1 (stable) editor for Linux x86_64.** `project.godot` declares
  feature `4.7`, so the exporting editor must be 4.7.x, and its export templates
  must be the exact same version (4.7.1.stable).
  Download `Godot_v4.7.1-stable_linux.x86_64.zip` from
  <https://github.com/godotengine/godot/releases/tag/4.7.1-stable>, unzip it, and
  either put the binary on `PATH` as `godot` (e.g. `/usr/local/bin/godot`) or
  point the script at it:

  ```sh
  GODOT=~/bin/Godot_v4.7.1-stable_linux.x86_64 tools/build.sh
  ```

  Check with `godot --version` (expect `4.7.1.stable.official...`).
- `curl` and `unzip` (only for the template download), `git` (optional; used to
  keep the tree clean), `file` (optional; used to check the output).

## Export templates

Godot looks for templates in
`~/.local/share/godot/export_templates/4.7.1.stable/` (or under
`$XDG_DATA_HOME` if set). Only three files are needed for this project:
`linux_release.arm64`, `linux_debug.arm64` and `version.txt` (containing
`4.7.1.stable`).

**Automatic:** `tools/build.sh --install-templates` (or `INSTALL_TEMPLATES=1`)
downloads the official 1.2 GB archive once, extracts those three files and
deletes the archive. Without the flag the script stops and prints the manual
steps if the templates are missing.

**Manual** (same result):

```sh
curl -fL --retry 5 -o /tmp/templates.tpz \
  https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz
T=~/.local/share/godot/export_templates/4.7.1.stable
mkdir -p "$T"
unzip -j -o /tmp/templates.tpz 'templates/linux_release.arm64' \
  'templates/linux_debug.arm64' 'templates/version.txt' -d "$T"
rm /tmp/templates.tpz
```

(The `.tpz` is a plain zip. The editor's *Editor > Manage Export Templates*
dialog also works but installs every platform, about 1.2 GB on disk.)

## Build

```sh
tools/build.sh                 # release build
tools/build.sh --debug         # debug template (console output, asserts)
tools/build.sh --help
```

| Option | Effect |
|---|---|
| `--install-templates` | Download and install the templates if missing |
| `--debug` | `--export-debug` instead of `--export-release` |
| `--no-import` | Skip the separate `godot --import` pass |
| `--keep-import-changes` | Keep the `*.import` files Godot rewrote (default: revert them) |

The script can be run from any directory. It:

1. checks that `$GODOT` (default `godot`) is 4.7.x and the templates are present;
2. checks the `Linux` preset in `export_presets.cfg` (arm64, no stale custom
   template paths);
3. runs `godot --headless --path . --import` to fill `.godot/` (about 15 s on a
   fresh clone on a desktop PC, a few seconds after that);
4. runs `godot --headless --path . --export-release "Linux" build/Soms-In-Space.arm64`
   (about 6 s);
5. verifies the result is an aarch64 ELF and prints its size (about 80 MB);
6. reverts `*.import` files that Godot rewrote (`git checkout -- '*.import'`,
   only those files, only inside a git work tree).

Output: `build/Soms-In-Space.arm64` (`build/` is git-ignored). The console
shows a lot of Godot progress output; the lines starting with `==>` are the
script's own.

## Deploy and run on the phyBOARD

```sh
scp build/Soms-In-Space.arm64 root@<board-ip>:/home/root/
ssh root@<board-ip>
chmod +x ./Soms-In-Space.arm64
./Soms-In-Space.arm64 --display-driver wayland --rendering-driver opengl3_es --fullscreen
```

The game is portrait (720x1280). To rotate a landscape screen, add an `[output]`
section with `transform=rotate-90` to `weston.ini`; see
[README.md](README.md#rotating-weston-display) for the HDMI and LVDS snippets.

## Kiosk behavior

Useful to know when leaving it running on a booth:

- **Attract mode:** after 20 s without input on the main menu, a demo run plays
  itself with the first ship; any touch or key ends it and opens ship select.
- **Idle return:** results and pause screens go back to the menu after 60 s; the
  credits and ship select screens after 30 s.
- **Ship select** starts on the first ship every time it opens, not on the
  previous visitor's pick.
- **High scores** are stored in `user://highscores.save`, on Linux
  `~/.local/share/godot/app_userdata/Soms-In-Space-GoDot-4-mobile/highscores.save`.
  Delete that file to clear the board. A save from an older scoring version
  is discarded on first launch.
- **Shield look:** `shield_style` in `data/game_config.tres` (Pickups group)
  switches the player's active shield between the hex dome art (`Sprite`) and
  the shader-only sphere (`Procedural`, the default). Re-export after changing it.

## Project layout

| Path | Contents |
|---|---|
| `scenes/` | Scenes: menus, `main_level.tscn`, `player.tscn`, and `obstacles/`, `collectibles/`, `effects/`, `ui/`, `misc/` |
| `scripts/` | GDScript, mirroring `scenes/`; autoloads `ScoreboardManager`, `ObjectPool`, `GameSession`, `AttractMode` |
| `data/` | Resources: `zones/` (per-zone waves and tuning), `ships/` (selectable ships), `paths/` (formation entry paths), `game_config.tres` (global caps) |
| `shaders/` | Atmosphere background and enemy hit flash |
| `sprites/`, `audio/`, `fonts/`, `materials/` | Assets |
| `addons/onscreenkeyboard/` | On-screen keyboard for high score name entry |
| `art_archive/` | Unused art kept for later; has a `.gdignore`, so Godot never imports or exports it ([README](art_archive/README.md)) |
| `docs/WAVE_DESIGN.md` | How waves, formations and zones are authored |
| `docs/ART_SWAP_TRACKER.md` | Every stand-in asset and where to swap in final art |
| `docs/UPGRADE_IDEAS.md` | Backlog of upgrades and the asset wishlist |
| `tools/build.sh` | This build |

## Placeholder art

Several features (some enemies, pickups and effects) run on
stand-in art. [docs/ART_SWAP_TRACKER.md](docs/ART_SWAP_TRACKER.md) lists each
one with the art it needs, and every spot in the code is tagged:

```sh
grep -rn PLACEHOLDER_ART scripts scenes data
```

### Art pipeline

Full-size art sources live in `art_archive/masters/` (ignored by Godot); the
game uses downscaled copies in `sprites/` (enemies and pickups 512 px tall,
UFO, blimp and docking station 1024 px wide, missiles 512 px along their length;
the ships keep their 1024x1536 canvas). An entry can crop the master (`crop`),
turn it in 90 degree steps (`rotate`, counter-clockwise: the sidewinder is drawn
nose-right and turned nose-up) and add a transparent margin (`pad`, e.g. the shield
sphere's 12% for its shader glow). A `sheet` entry repacks an animation strip whose frames are
not on a grid (the shield and health pickup icons) into a uniform horizontal sheet of
square cells: per frame a column span and a center that stays fixed across frames, a
common extent, and a minimum padding the run checks. After
adding or changing a master, add or adjust its row in the `ART` table of
`tools/resize_art.gd`, then regenerate and re-import:

```sh
godot --headless --path . -s res://tools/resize_art.gd
godot --headless --path . --import
```

The existing `.import` files (UIDs, `mipmaps/generate=true` for the downscaled
enemy and pickup textures) are kept, so scenes stay wired. A new texture's
sprite scale is `old scale x old size / new size` for the same on-screen size.

## Troubleshooting

- **"No export template found" / "Custom debug template not found".** The
  template folder name must match the editor version exactly
  (`4.7.1.stable`), and `custom_template/debug` / `custom_template/release` in
  `export_presets.cfg` must be empty (`""`). Older commits pointed them at a
  local engine build; the script detects that and stops.
- **Output is x86_64, or the board says "cannot execute binary file".** The
  preset's `binary_format/architecture` must be `"arm64"`. If the editor's
  Export dialog was used, check it did not reset this.
- **"Invalid UID" / "unrecognized UID" warnings** during import or export are
  benign: Godot falls back to the `res://` path and the export is complete.
- **Lots of modified `*.import` files** after opening the project in the
  editor or exporting with `--keep-import-changes`: Godot 4.7 rewrites them in
  its own format. Harmless; discard with `git checkout -- '*.import'`, or commit
  them once in a dedicated change if the whole team is on 4.7.
- **New `*.gd.uid` / `*.gdshader.uid` files** appear after an import: Godot 4.4+
  generates one per script/shader. They belong in git; commit them with the
  script they belong to.
- **Window does not open / X11 errors on the board.** Pass
  `--display-driver wayland` and make sure Weston is running (the project's
  default driver is already `wayland`). `export WAYLAND_DEBUG=1` shows the
  protocol traffic.
- **Black screen or Vulkan errors on the board.** The AM62x GPU needs the
  compatibility renderer: always pass `--rendering-driver opengl3_es`.
- **Textures look wrong on the board.** They should not: all textures import
  lossless, so the preset's desktop texture format flags (`s3tc_bptc`) do not
  affect the arm64 build.
