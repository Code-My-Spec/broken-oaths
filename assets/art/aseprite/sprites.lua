-- Broken Oaths sprite set v1 — authored as 16x16 pixel maps, exported
-- 2x (32x32 PNG) for the game board billboards (see ADR
-- game-art-pipeline.md). Run headless:
--
--   aseprite -b --script assets/art/aseprite/sprites.lua
--
-- Palette letters are per-sprite; "." is transparent. Outline K matches
-- the board's existing unit ring (#1a1a1a). Unit identity colors match
-- the current circles (lord #f5c542, settler #42a5f5).

local OUT_PNG = "priv/static/images/game/"
local OUT_ASE = "assets/art/aseprite/"

local function rgba(hex, alpha)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  return app.pixelColor.rgba(r, g, b, alpha or 255)
end

local function build(name, subdir, palette, rows)
  assert(#rows == 16, name .. ": expected 16 rows, got " .. #rows)
  local spr = Sprite(16, 16, ColorMode.RGB)
  local img = spr.cels[1].image

  for y, row in ipairs(rows) do
    assert(#row == 16, name .. " row " .. y .. ": expected 16 chars, got " .. #row)
    for x = 1, 16 do
      local ch = row:sub(x, x)
      if ch ~= "." then
        local color = palette[ch]
        assert(color, name .. " row " .. y .. ": unknown palette char '" .. ch .. "'")
        img:putPixel(x - 1, y - 1, color)
      end
    end
  end

  spr:saveAs(OUT_ASE .. name .. ".aseprite")
  spr:resize(32, 32)
  spr:saveCopyAs(OUT_PNG .. subdir .. "/" .. name .. ".png")
  spr:close()
  print("built " .. subdir .. "/" .. name)
end

-- ---------------------------------------------------------------- lord
build("lord", "units", {
  K = rgba("#1a1a1a"),
  G = rgba("#f5c542"), -- gold
  D = rgba("#c9971e"), -- dark gold
  S = rgba("#eab887"), -- skin
  R = rgba("#a83232"), -- cape red
  W = rgba("#fff3c4"), -- gold highlight
}, {
  "................",
  "....K.K.K.......",
  "....KGKGKGK.....",
  "....KWGGGWK.....",
  "....KSSSSSK.....",
  "....KSKSKSK.....",
  "....KSSSSSK.....",
  "...KKGGGGGKK....",
  "..KRKGDGDGKRK...",
  "..KRKGGGGGKRK...",
  "..KRKGDGDGKRK...",
  "...KKGGGGGKK....",
  "....KGGKGGK.....",
  "....KGK.KGK.....",
  "...KKKK.KKKK....",
  "................",
})

-- ------------------------------------------------------------- settler
build("settler", "units", {
  K = rgba("#1a1a1a"),
  B = rgba("#42a5f5"), -- tunic blue
  N = rgba("#2a6db3"), -- dark blue
  S = rgba("#eab887"), -- skin
  H = rgba("#8a5a2b"), -- hat brown
  T = rgba("#b07a3e"), -- bindle stick
  W = rgba("#e8e2d0"), -- bundle cloth
}, {
  "................",
  ".....KKKKK......",
  "....KHHHHHK.KK..",
  "...KHHHHHHHKWWK.",
  "....KSSSSSKKWWK.",
  "....KSKSKSK.KK..",
  "....KSSSSSK.KT..",
  "...KKBBBBBKKKT..",
  "..KBKBBNBBK.KT..",
  "..KBKBBBBBK.KT..",
  "..KBKBBNBBK.....",
  "...KKBBBBBKK....",
  "....KBBKBBK.....",
  "....KBK.KBK.....",
  "...KKKK.KKKK....",
  "................",
})

-- ------------------------------------------------------------ mountain
build("mountain", "decor", {
  K = rgba("#1a1a1a"),
  A = rgba("#6b7280"), -- rock
  L = rgba("#9ca3af"), -- light rock
  W = rgba("#f1f5f9"), -- snow
}, {
  "................",
  "......KK........",
  ".....KWWK.......",
  "....KWWWWK......",
  "....KLWWLK.KK...",
  "...KLLWWLLKWWK..",
  "...KLALLALKWWLK.",
  "..KLAAAAALKLLAK.",
  "..KAAALAAAKALAK.",
  ".KAAALLAAAALAAK.",
  ".KAALAAAAAAAALK.",
  "KAAAAAAALAAAAAAK",
  "KKKKKKKKKKKKKKKK",
  "................",
  "................",
  "................",
})

-- --------------------------------------------------------------- hills
build("hills", "decor", {
  K = rgba("#1a1a1a"),
  E = rgba("#8a9a56"), -- hill green
  D = rgba("#6f7f42"), -- hill shade
}, {
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
  "....KKKK........",
  "..KKEEEEKK.KKK..",
  ".KEEEDEEEEKEEEK.",
  "KEEEEEEEDEKEDEEK",
  "KKKKKKKKKKKKKKKK",
  "................",
  "................",
  "................",
  "................",
  "................",
})

-- --------------------------------------------------------------- woods
build("woods", "decor", {
  K = rgba("#1a1a1a"),
  F = rgba("#15803d"), -- pine
  E = rgba("#0f5c2c"), -- pine shade
  T = rgba("#7a4a1f"), -- trunk
}, {
  "......KK........",
  ".....KFFK.......",
  ".....KFEK.......",
  "....KFFFFK.KK...",
  "....KFEFFKKFFK..",
  "...KFFFFFKKFEK..",
  "...KFEFFFKKFFFK.",
  "..KFFFFFFFKFEFK.",
  "..KFEFFFEFKFFFK.",
  ".KFFFFFFFFKKKKK.",
  ".KKKKKTKKKK.KTK.",
  ".....KTK....KTK.",
  "....KKTKK..KKTKK",
  "................",
  "................",
  "................",
})

-- ---------------------------------------------------------- rainforest
build("rainforest", "decor", {
  K = rgba("#1a1a1a"),
  J = rgba("#065f46"), -- canopy dark
  L = rgba("#0a8a5f"), -- canopy light
  T = rgba("#5f3a18"), -- trunk
}, {
  "................",
  "....KKK..KKK....",
  "...KLLJKKJLLK...",
  "..KLJJLJJLJJLK..",
  ".KJJLJJKLJJLJJK.",
  ".KLJJJLKJJLJJLK.",
  ".KJLJJJKLJJJLJK.",
  ".KKJJLJKJLJJKK..",
  "..KKKJKKKJKKK...",
  "....KTK.KTK.....",
  "....KTK.KTK.....",
  "....KTK.KTK.....",
  "...KKTKKKTKK....",
  "................",
  "................",
  "................",
})

-- ---------------------------------------------------------------- city
build("city", "decor", {
  K = rgba("#1a1a1a"),
  T = rgba("#c9a55a"), -- thatch
  D = rgba("#a3823f"), -- thatch shade
  W = rgba("#8a5a2b"), -- wall wood
  V = rgba("#6b4520"), -- wall shade / door
  F = rgba("#a83232"), -- banner
}, {
  "............K...",
  "...........KFK..",
  "......KK...KFFK.",
  ".....KTTK..KFK..",
  "....KTTDTK..K...",
  "...KTTTTDTK.K...",
  "..KTDTTTTTTKK...",
  ".KTTTTDTTTTDK...",
  ".KKKKKKKKKKKK...",
  "..KWWVWWVWWK....",
  "..KWWKVVKWWK....",
  "..KWWKVVKWWK....",
  ".KKKKKKKKKKKK...",
  "................",
  "................",
  "................",
})

print("sprite set complete")
