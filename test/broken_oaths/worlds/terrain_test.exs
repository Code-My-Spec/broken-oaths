defmodule BrokenOaths.Worlds.TerrainTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.Terrain

  test "water?/1" do
    assert Terrain.water?(%Terrain{base: :ocean})
    assert Terrain.water?(%Terrain{base: :coast})
    refute Terrain.water?(%Terrain{base: :grassland})
  end

  describe "color/1" do
    test "base colors pass through for flat land" do
      assert Terrain.color(%Terrain{base: :grassland}) == "#22c55e"
      assert Terrain.color(nil) == "#1e3a8a"
    end

    test "features overlay the base" do
      assert Terrain.color(%Terrain{base: :grassland, feature: :woods}) == "#15803d"
      assert Terrain.color(%Terrain{base: :plains, feature: :woods}) == "#15803d"
    end

    test "relief shades through: hills darken, mountains gray" do
      flat = Terrain.color(%Terrain{base: :grassland})
      hills = Terrain.color(%Terrain{base: :grassland, relief: :hills})
      mountains = Terrain.color(%Terrain{base: :grassland, relief: :mountains})

      assert flat != hills and hills != mountains
      # Woods on hills is darker than woods on flat
      assert Terrain.color(%Terrain{base: :grassland, feature: :woods, relief: :hills}) !=
               Terrain.color(%Terrain{base: :grassland, feature: :woods})
    end

    test "all colors are well-formed hex and round-trip to rgb bytes" do
      for base <- [:ocean, :coast, :grassland, :plains, :desert, :tundra, :snow],
          relief <- [:flat, :hills, :mountains],
          feature <- [nil, :woods, :rainforest, :marsh, :ice] do
        terrain = %Terrain{base: base, relief: relief, feature: feature}
        color = Terrain.color(terrain)
        assert color =~ ~r/^#[0-9a-f]{6}$/

        {r, g, b} = Terrain.rgb_bytes(terrain)
        assert r in 0..255 and g in 0..255 and b in 0..255
      end
    end
  end

  describe "label/1" do
    test "composes base, relief and feature" do
      assert Terrain.label(%Terrain{base: :grassland}) == "Grassland"
      assert Terrain.label(%Terrain{base: :plains, relief: :hills}) == "Plains Hills"

      assert Terrain.label(%Terrain{base: :plains, relief: :hills, feature: :rainforest}) ==
               "Plains Hills · Rainforest"

      assert Terrain.label(%Terrain{base: :snow, relief: :mountains}) == "Snow Mountains"
      assert Terrain.label(nil) == "—"
    end
  end

  test "legend has distinct labels and valid colors" do
    legend = Terrain.legend()
    labels = Enum.map(legend, fn {_c, l} -> l end)
    assert length(Enum.uniq(labels)) == length(labels)

    for {color, _label} <- legend do
      assert color =~ ~r/^#[0-9a-f]{6}$/
    end
  end
end
