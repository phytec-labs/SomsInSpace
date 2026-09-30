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
