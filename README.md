# AncientWorld

Roblox place. The Luau sources live in `src/`, mirroring the instance tree
(`src/<Service>/<Folder>/<Script>.luau`); `AncientWorld.rbxlx` is the built place file.

## Rebuilding the place

```sh
python3 tools/build.py AncientWorld.rbxlx src AncientWorld.rbxlx
```

The build replaces the `Source` of every script in the place with its file from `src/` and
adds a `ModuleScript` for any new `.luau` file. Parts, folders and other instances are kept.

- `tools/extract.py <place.rbxlx> src` — dump the scripts of a place file back into `src/`.
- `tools/inspect.py <place.rbxlx>` — print the instance tree.
- `tools/prefabs.py check` — verify the geometry of the masonry and lighting prefabs (bounds, coplanar faces);
  `tools/prefabs.py gen` prints the irregular stone tables used by the cobblestone road and ruin wall.
