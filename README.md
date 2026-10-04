# Cone Vision Outline

A Project Zomboid (Build 42) client mod. Outlines zombies and animals that are in
your vision cone while aiming (RMB): white for cone targets, green for melee
hit-list targets. Firearms draw no outline. Respects the ShortSighted trait.

- Steam Workshop: <https://steamcommunity.com/sharedfiles/filedetails/?id=3659137034>
- Requires the game option **Display → Melee outline** to be enabled.
- Singleplayer, multiplayer and split-screen. Server admins can enforce the gameplay
  options for all players through the mod's Sandbox options page.
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
    └── media/
        ├── sandbox-options.txt           server-side Sandbox page (enforce settings for all players)
        └── lua/
            ├── client/
            │   ├── ConeVisionOutline.lua         the outline logic (OnPlayerUpdate)
            │   └── ConeVisionOutline_Options.lua mod options (Settings → Mods) + Sandbox override
            └── shared/Translate/
                ├── {EN,RU,CN}/UI.json            mod option strings
                └── {EN,RU}/Sandbox.json          Sandbox page strings
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

## Multiplayer and split-screen

The mod is client-side only, and that is enough: `setOutlineHighlight` is local render
state and sends nothing, so every client computes its own outlines. `OnPlayerUpdate` fires
only for local players — once per tick normally, once per player in split-screen — so all
state (outlined objects, hit-list colours, the floor-above overlay) is kept per local
player and written to that player's outline slot.

The only server-side piece is `media/sandbox-options.txt`. With **Enforce these settings
for all players** on, `ConeVisionOutline_Options.lua` replaces the player's own values with
the server's `SandboxVars.ConeVisionOutline` (multiplayer only; the outline colour is never
enforced). There is no "sandbox changed" event, so it is re-applied every in-game minute.

Known limitation (split-screen only): the engine paints the melee hit list for all local
players at once, so two players aiming melee at the same targets both see them green.

## Building / publishing

There is no build step. Copy the tree into the game's Workshop staging folder
(`%USERPROFILE%\Zomboid\Workshop\ConeVisionOutline\`), then publish from the game's
main menu → Workshop → Submit. Lua is read at startup — restart the game to test.

## License

MIT. See [LICENSE](LICENSE).
