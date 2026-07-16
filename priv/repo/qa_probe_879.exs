# QA probe script for story 879 — PURE reads only (Worlds/Globe/Terrain/Regions),
# never BrokenOaths.Game.* (would start a competing WorldServer).
# Usage: mix run priv/repo/qa_probe_879.exs

world1 = BrokenOaths.Worlds.get_world!(1)
world6 = BrokenOaths.Worlds.get_world!(6)

IO.inspect(BrokenOaths.Worlds.Regions.terrain(world1, 6526), label: "world1 settler(20) tile 6526 terrain")
IO.inspect(BrokenOaths.Worlds.Regions.tile_class(world1, 6526), label: "world1 tile 6526 tile_class")
IO.inspect(BrokenOaths.Worlds.Regions.adjacent_tiles(world1, 6526), label: "world1 tile 6526 adjacent")
IO.inspect(BrokenOaths.Worlds.Regions.terrain(world1, 6569), label: "world1 lord(19) tile 6569 terrain")

IO.inspect(BrokenOaths.Worlds.Regions.adjacent_tiles(world6, 21635), label: "world6 city tile 21635 adjacent")
for t <- BrokenOaths.Worlds.Regions.adjacent_tiles(world6, 21635) do
  IO.inspect({t, BrokenOaths.Worlds.Regions.tile_class(world6, t)}, label: "world6 neighbor tile_class")
end

IO.puts("\n--- city4 territory yields (world1) ---")
for t <- [6483,6484,6525,6526,6527,6567,6568,6440] do
  terrain = BrokenOaths.Worlds.Regions.terrain(world1, t)
  IO.inspect({t, terrain}, label: "tile")
end
