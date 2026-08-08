# Pokemove Colorfix

Battle move animations in [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) render as
two-tone white-and-black. This gives every one of them a palette drawn from its move's
elemental type — Ember burns orange, Thundershock is yellow, Surf is blue.

Install with **Launcher → MODS → Import mod .zip**.

## Why they are colorless

`AnimPlayer`'s `placeTile` stamps every frame-block tile with

```lua
obp = t.pal1 and "obp1" or "f0"
```

and `BattleState`'s `OBJ_SHADES` maps those onto shade indices of the palette zone
underneath:

```
f0   = { 0, 3, 3 }   color 1 -> lightest, colors 2 and 3 -> darkest
f0x  = { 3, 0, 3 }   the Master/Ultra ball flicker ($f0 xor %00111100)
e4   = { 1, 2, 3 }   identity
obp1 = { 3, 2, 1 }
```

So every tile not flagged `pal1` collapses to exactly **two** visible shades: the
near-white and near-black anchors. Hue lives in shades 1 and 2, which `f0` never selects.

That is faithful — on hardware these animations run under `wAnimPalette $f0` and genuinely
are monochrome. It is also why **no COLORS palette mod can fix it**: the hue is discarded
before any palette is consulted.

This mod replaces that mapping for move animations with a fixed three-stop ramp, so the
sprite's three colors become highlight / body / edge instead of white / black / black.

## How colors are chosen

Not by indexing 165 moves. `moveAnims` is keyed by move name and `data.moves[id].type`
gives the element, so **15 type ramps cover every move**, with a small exception list for
the few that read wrong in their own type's colors (Explosion and Self-Destruct borrow
Fire; Hyper Beam gets its own violet).

Both tables are at the top of `main.lua` as plain 0–255 RGB. Ramps must fall in brightness
across the row — light to dark — or the effect renders inside out.

## What it deliberately leaves alone

- `obp1` and `e4` sprites, which already resolve the full range.
- Animations with no entry in `data.moves` — the ball toss, POOF, the send-out and status
  chains. These fall through to the engine, so they stay owned by **Pokeball Colorfix** if
  that is installed.

## The WIDE layout bug

`BattleState:draw` diverts to `WideBattle.draw`, whose `drawAnimationLayer` calls
`battle:drawAnimLayer(false)` — no color function, so the shade-remap shader is skipped
entirely and raw DMG grays are blitted. The OG layout passes `true` on the same call.
Without fixing that, nothing this mod does is visible in the wide layout, so it patches it
too.

This is a real engine bug affecting every battle animation sprite for wide-layout players.
**Pokeball Colorfix** patches it independently; applying both is harmless, since each only
forces a flag that is already being forced to the same value.

## Notes

- Requires `engine_internals`; it patches engine functions rather than shipping art.
- No ROM data or game assets are included.
- Composes with **Pokeball Colorfix** in either load order.

## Status

Untested. If effects look inside out — dark where they should be bright — colors 1 and 3
are swapped for those sprites, which is a one-line change.
