defmodule BrokenOaths.Worlds.WeatherTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.{Globe, Weather}

  @seed 424_242
  @frequency 8

  test "map is sparse, leveled 1..3, deterministic, seed-dependent" do
    mesh = Globe.get(@frequency)
    map = Weather.map(@seed, mesh)

    assert map != %{}
    # Sparse: clear tiles are absent, so the map is a strict subset
    assert map_size(map) < Globe.tile_count(@frequency)

    for {id, level} <- map do
      assert is_integer(id) and id >= 0 and id < Globe.tile_count(@frequency)
      assert level in 1..3
    end

    assert Weather.map(@seed, mesh) == map
    refute Weather.map(@seed + 1, mesh) == map
  end

  test "weather changes between epochs but is deterministic within one" do
    mesh = Globe.get(@frequency)

    epoch_0 = Weather.map(@seed, mesh, 0)
    epoch_1 = Weather.map(@seed, mesh, 1)

    refute epoch_1 == epoch_0
    assert Weather.map(@seed, mesh, 1) == epoch_1
    assert epoch_1 != %{}
  end

  test "level/3 returns 0 for clear tiles and the mapped level otherwise" do
    mesh = Globe.get(@frequency)
    map = Weather.map(@seed, mesh)

    {cloudy_id, level} = Enum.at(map, 0)
    assert Weather.level(@seed, mesh, cloudy_id) == level

    clear_id = Enum.find(0..(Globe.tile_count(@frequency) - 1), &(!Map.has_key?(map, &1)))
    assert Weather.level(@seed, mesh, clear_id) == 0
  end

  test "palette covers levels 0..3 with rising opacity" do
    palette = Weather.palette()
    alphas = for l <- 0..3, do: elem(palette[l], 3)
    assert alphas == Enum.sort(alphas)
    assert hd(alphas) == 0
  end
end
