-- Pokemove Colorfix
--
-- Ember, Thundershock and every other move animation render as two-tone
-- white-and-black. This gives each one a palette drawn from its move's
-- elemental type.
--
-- ------- why they are colorless in the first place
--
-- AnimPlayer's placeTile stamps every frame-block tile with
--
--     obp = t.pal1 and "obp1" or "f0"
--
-- and BattleState's OBJ_SHADES maps those to shade indices of the zone
-- palette underneath:
--
--     f0   = { 0, 3, 3 }    sprite color 1 -> lightest, colors 2 and 3 -> darkest
--     obp1 = { 3, 2, 1 }    the full range, reversed
--
-- So the overwhelming majority of animation tiles -- everything not flagged
-- pal1 -- collapse to exactly TWO visible shades: the near-white and
-- near-black anchors of whatever palette is under them. Hue lives in shades
-- 1 and 2, which f0 never selects. That is faithful: on hardware these run
-- under wAnimPalette $f0 and genuinely are monochrome. It is also why no
-- COLORS palette mod can help -- the information is discarded before the
-- palette is ever consulted.
--
-- This mod replaces that mapping for move animations with a fixed three-stop
-- ramp per elemental type, so the sprite's own three colors become
-- highlight / body / edge instead of white / black / black.
--
-- ------- what it deliberately does not touch
--
--   * obp1 and e4 sprites, which already resolve the full range
--   * animations with no entry in data.moves -- the ball toss, POOF, the
--     send-out and status chains -- which fall through to the engine (and
--     so stay owned by Pokeball Colorfix if that is installed)
--
-- ------- composing with Pokeball Colorfix
--
-- Both mods wrap animSpriteColors and both call through for sprites they do
-- not own, so they compose in either load order. The sets are disjoint:
-- TOSS_ANIM and friends are miscAnimations, not moves, so this mod never
-- claims them. The drawAnimLayer patch below is the same one Pokeball Colorfix
-- applies; applying it twice is harmless, since it only ever forces a flag
-- that is already being forced to the same value.

return function(mod)
  local BattleState = require("src.battle.BattleState")
  local AnimPlayer  = require("src.battle.AnimPlayer")

  -- highlight / body / edge, per elemental type. Ordered light to dark:
  -- these become sprite colors 1, 2 and 3, and a ramp that does not fall in
  -- brightness will read inside out.
  local TYPES = {
    NORMAL   = { { 248, 248, 248 }, { 184, 184, 184 }, {  56,  56,  56 } },
    FIGHTING = { { 255, 208, 160 }, { 216,  96,  48 }, {  96,  24,  16 } },
    FLYING   = { { 176, 222, 255 }, { 160, 200, 240 }, {  56,  88, 144 } },
    POISON   = { { 240, 200, 255 }, { 184,  88, 208 }, {  72,  24,  96 } },
    GROUND   = { { 240, 216, 160 }, { 200, 152,  72 }, {  88,  56,  16 } },
    ROCK     = { { 232, 206, 160 }, { 160, 136, 104 }, {  64,  48,  32 } },
    BUG      = { { 224, 248, 176 }, { 152, 200,  72 }, {  56,  88,  24 } },
    GHOST    = { { 214, 186, 255 }, { 136, 104, 200 }, {  40,  24,  72 } },
    FIRE     = { { 255, 240, 176 }, { 248, 144,  40 }, { 152,  32,  16 } },
    WATER    = { { 168, 224, 255 }, {  72, 160, 232 }, {  24,  64, 136 } },
    GRASS    = { { 216, 248, 176 }, {  88, 192,  88 }, {  24,  88,  40 } },
    ELECTRIC = { { 255, 255, 200 }, { 248, 216,  48 }, { 136,  88,   8 } },
    PSYCHIC  = { { 255, 184, 232 }, { 240, 104, 184 }, { 112,  24,  88 } },
    ICE      = { { 176, 236, 255 }, { 136, 216, 240 }, {  40, 104, 144 } },
    DRAGON   = { { 196, 196, 255 }, { 128, 128, 216 }, {  40,  40,  96 } },
  }

  -- Moves whose animation reads wrong in its type's colors. Kept small on
  -- purpose: the type table is the rule, this is the exception list.
  local MOVES = {
    -- NORMAL, but they are explosions
    EXPLOSION   = TYPES.FIRE,
    SELFDESTRUCT = TYPES.FIRE,
    -- NORMAL, but the animation is a beam and deserves to look like one
    HYPER_BEAM  = { { 255, 196, 255 }, { 216, 104, 232 }, {  88,  16, 112 } },
  }

  -- ------- why the highlight stops carry real chroma
  --
  -- Sprite colour 1 is the stop most animations lean on hardest, and a beam
  -- tile can be almost nothing else. A highlight only a few points off white
  -- therefore renders the whole move white -- which is exactly what the
  -- vanilla f0 map does, so the mod appears to have done nothing. Psybeam was
  -- the case that caught it: (255,216,240) is 39 points of chroma, invisible
  -- at 8x8 on a handheld. Every stop here now clears ~60 points.
  --
  -- NORMAL is the deliberate exception: a Tackle impact should read as a
  -- plain white flash, not a tinted one.

  -- The type CONSTANT is not always the type NAME. pokered disambiguates
  -- Psychic's constant to PSYCHIC_TYPE because there is also a move called
  -- PSYCHIC, so `moves.PSYBEAM.type` is "PSYCHIC_TYPE" and a table keyed
  -- "PSYCHIC" silently misses -- which left every Psychic move rendering
  -- vanilla white. Stripping the suffix is done generically rather than
  -- aliasing the one known case, so a future constant with the same shape
  -- resolves on its own. PSYCHIC_TYPE is the only such name today.
  local function rampForType(t)
    if type(t) ~= "string" or t == "" then return nil end
    return TYPES[t] or TYPES[(t:gsub("_TYPE$", ""))]
  end

  local function paletteFor(moveId, data)
    if not moveId then return nil end
    local direct = MOVES[moveId]
    if direct then return direct end
    local moves = data and data.moves
    local def = moves and moves[moveId]
    -- no move record: a miscAnimation (ball toss, POOF, status chains).
    -- Left to the engine deliberately -- see the header.
    if not def then return nil end
    return rampForType(def.type)
  end

  -- ------- 1. the WIDE layout never colorizes the anim layer at all
  --
  -- BattleState:draw hands off to WideBattle.draw, whose drawAnimationLayer
  -- calls drawAnimLayer(false) -- no color function, so the shade-remap
  -- shader is skipped and raw DMG grays are blitted. Without this, nothing
  -- below is visible in that layout. Guarded on colorMode() because the flat
  -- fallback calls drawAnimLayer(false) too and has no shader to hand over.
  if not BattleState._moveColorsOriginalDraw then
    BattleState._moveColorsOriginalDraw = BattleState.drawAnimLayer
  end
  local originalDraw = BattleState._moveColorsOriginalDraw

  function BattleState:drawAnimLayer(colorized)
    if not colorized and self.wideLayout and self:wideLayout()
       and self:colorMode() then
      colorized = true
    end
    return originalDraw(self, colorized)
  end

  -- ------- 2. remember which animation is playing
  if not AnimPlayer._moveColorsOriginalStart then
    AnimPlayer._moveColorsOriginalStart = AnimPlayer.start
  end
  local originalStart = AnimPlayer._moveColorsOriginalStart

  function AnimPlayer:start(moveId, attackerIsPlayer, opts)
    self._mcMove = moveId
    return originalStart(self, moveId, attackerIsPlayer, opts)
  end

  -- ------- 3. hand f0 sprites the type ramp
  --
  -- Only f0 and its flicker twin f0x. obp1 and e4 are left to the engine on
  -- purpose: both map to the full shade range, so they already resolve real
  -- colour and were never the broken case.
  --
  -- 1.1.1 briefly claimed obp1 as well, on the theory that Psybeam staying
  -- white meant its beam had to be a PAL1 tile. That reasoning was wrong --
  -- white only proved this mod had not claimed the sprite, not which slot it
  -- used. The real cause was the PSYCHIC_TYPE lookup miss above. Tested
  -- afterwards: with the obp1 handling disabled, Psybeam stays pink. So it
  -- was changing sprites that were never broken, for no benefit, and it is
  -- gone. Recorded here so it does not get re-tried on the same hunch.
  if not BattleState._moveColorsOriginalColors then
    BattleState._moveColorsOriginalColors = BattleState.animSpriteColors
  end
  local originalColors = BattleState._moveColorsOriginalColors

  local function norm(c) return { c[1] / 255, c[2] / 255, c[3] / 255 } end

  function BattleState:animSpriteColors(s, px, py)
    local obp = s and s.obp
    if obp ~= "f0" and obp ~= "f0x" then
      return originalColors(self, s, px, py)
    end
    local ap = self.animPlayer
    local pal = ap and paletteFor(ap._mcMove, self.data)
    if not pal then return originalColors(self, s, px, py) end
    local hi, mid, lo = pal[1], pal[2], pal[3]
    if obp == "f0x" then
      -- the hardware flicker complements colors 1 and 2
      hi, mid = mid, hi
    end
    return { norm(hi), norm(mid), norm(lo) }
  end
end
