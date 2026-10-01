# art_archive

Art and resource files that are not currently referenced by any scene, script,
or resource in the game. They are kept here (instead of deleted) so they can be
reused in a later upgrade phase without bloating the embedded export.

This folder contains a `.gdignore` file, so Godot ignores it completely: nothing
in here is imported, shown in the FileSystem dock, or included in exports.

## Restoring a file

1. Move it back to its original path by dropping the `art_archive/` prefix, e.g.

   ```sh
   git mv "art_archive/sprites/Laser Sprites/01.png" "sprites/Laser Sprites/01.png"
   ```

2. Open the project in the Godot editor. Godot re-imports the file and
   regenerates its `.import` file (the old `.import` files were removed, since
   they are recreated automatically). Commit the new `.import` file.

Note: a re-imported file gets a new `uid://`, so reference it by its `res://`
path when adding it back to a scene or script.

## masters/

Full-size sources of art the game uses (jets, drone, mine, UFO, zeppelin sheet,
bomb icon, shield sphere, docking station, shield and health pickup animation strips).
The game uses downscaled copies in `sprites/` (same basenames, except the blimp:
`sprites/zeppelin_1.png` is the zeppelin cut out of `zeppelin_weapon_combined.png`, whose
six weapon modules are not used yet; and the two pickup strips,
`shield_icon_sprite_sheet.png` and `health_pickup_sprite_sheet.png`, which are repacked
into the uniform 256 px-cell sheets `sprites/shield_icon_sheet.png` and
`sprites/health_pickup_sheet.png`).
To regenerate the game copies after editing a master:

```sh
godot --headless --path . -s res://tools/resize_art.gd
godot --headless --path . --import
```

The size table lives in `tools/resize_art.gd`; conventions are in
`docs/ART_SWAP_TRACKER.md`. Do not move masters back into `sprites/`: Godot
would import them at full size.

## art_old/

The previous pixel-art versions of `jet_1.png`, `jet_2.png` and `jet_8.png`,
replaced by the new jet_1 / jet_2 / jet_3 art.
`shield_dome_half.png` is the previous half-dome shield master (1261x1247),
replaced by the full sphere in `masters/shield_dome_1.png`.
