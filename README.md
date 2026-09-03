# Cone Vision Outline

A Project Zomboid (Build 42) client mod. Outlines zombies and animals that are in
your vision cone while aiming (RMB): white for cone targets, green for melee
hit-list targets. Firearms draw no outline. Respects the ShortSighted trait.

- Steam Workshop: <https://steamcommunity.com/sharedfiles/filedetails/?id=3659137034>
- Requires the game option **Display → Melee outline** to be enabled.
- Single player. Multiplayer is untested.
- Hit-list logic originally from *Aim Outline* by Kreb (Workshop ID 3404684285).
  Engine-visibility approach found by reading *RadVision* (Workshop ID 3774647043).

## Repository layout

This is the mod's working copy (source of truth). Nothing reads it directly — it
is copied into the game's staging folder and published from there.

```
workshop.txt                              Workshop item metadata (title, id, description, tags)
preview.png                               Workshop item preview
Contents/mods/ConeVisionOutline/
├── common/                               version-agnostic assets (currently empty)
└── 42/                                   Build 42 payload (pzversion in mod.info)
    ├── mod.info                          name, id, modversion
    ├── poster.png
    └── media/lua/
        ├── client/
        │   ├── ConeVisionOutline.lua     the outline logic (OnPlayerUpdate)
        │   └── ConeVisionOutline_Options.lua   mod options (Settings → Mods)
        └── shared/Translate/{EN,RU}/     UI strings (.json is what B42 loads; .txt kept for reference)
```

## How it works

`ConeVisionOutline.lua` runs on `Events.OnPlayerUpdate`. Each frame, while aiming
(or per the "always on" options), it walks the cell object list, and for each
zombie/animal that the engine considers visible it calls
`setOutlineHighlight` / `setOutlineHighlightCol`.

- **Visibility (default):** `IsoObject:isTargetAlphaZero(playerNum)` — the engine's
  own per-object verdict (view distance, cone, line of sight, light). "Legacy
  outline mode" falls back to `IsoGridSquare:isCanSee` plus the mod's own cone math.
- **Melee hit list:** identified without reflection. `CombatManager.highlightTargets`
  repaints the real hit list each frame before this event runs, so an object whose
  outline colour no longer matches what the mod wrote last frame is in the hit list
  and gets painted green.
- **Floor-above indicator:** targets one Z level up (top of stairs) that the engine
  will not outline get a pulsing 2D overlay circle instead.
- Optional dimming by tile light level and by world fog thickness.

Lua errors from the per-frame loop are reported once each to `console.txt` rather
than being swallowed, so future engine API changes stay visible.

## Building / publishing

There is no build step. Copy the tree into the game's Workshop staging folder
(`%USERPROFILE%\Zomboid\Workshop\ConeVisionOutline\`), then publish from the game's
main menu → Workshop → Submit. Lua is read at startup — restart the game to test.

## License

MIT. See [LICENSE](LICENSE).
