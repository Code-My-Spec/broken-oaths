defmodule BrokenOaths.Worlds.TextureTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.{Globe, Texture}

  @frequency 8
  @seed 12345

  test "dims come from test config" do
    assert Texture.dims() == {128, 64}
  end

  describe "index/3" do
    test "every pixel maps to a valid tile id" do
      {w, h} = Texture.dims()
      ids = Texture.index(@frequency, w, h)
      n = Globe.tile_count(@frequency)

      for i <- 1..(w * h) do
        assert :atomics.get(ids, i) < n
      end
    end

    test "the top row maps to the north-pole tile, bottom row to the south pole" do
      {w, h} = Texture.dims()
      ids = Texture.index(@frequency, w, h)

      mesh = Globe.get(@frequency)
      south_id = Globe.nearest_tile(mesh, {0.0, 0.0, -1.0}).id

      for px <- Enum.take_every(0..(w - 1), 16) do
        assert :atomics.get(ids, px + 1) == 0
        assert :atomics.get(ids, (h - 1) * w + px + 1) == south_id
      end
    end

    test "equator pixels map to nearby tiles" do
      {w, h} = Texture.dims()
      ids = Texture.index(@frequency, w, h)
      mesh = Globe.get(@frequency)

      for px <- Enum.take_every(0..(w - 1), 16) do
        py = div(h, 2)
        id = :atomics.get(ids, py * w + px + 1)

        lon = 2 * :math.pi() * ((px + 0.5) / w - 0.5)
        lat = :math.pi() * (0.5 - (py + 0.5) / h)
        p = {:math.cos(lat) * :math.cos(lon), :math.cos(lat) * :math.sin(lon), :math.sin(lat)}

        {cx, cy, cz} = Globe.tile(mesh, id).center
        {px_, py_, pz_} = p
        dot = cx * px_ + cy * py_ + cz * pz_

        # Within a tile-spacing or so of the pixel direction
        assert dot > :math.cos(2 * 1.107 / @frequency)
      end
    end
  end

  describe "png/2" do
    test "produces a valid palette PNG of the configured size" do
      png = Texture.png(@seed, @frequency)
      {w, h} = Texture.dims()

      # magic
      assert <<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>> = png
      # IHDR: size, bit depth 8, color type 3 (palette)
      assert <<_len::32, "IHDR", ^w::32, ^h::32, 8, 3, 0, 0, 0, _crc::32, rest2::binary>> = rest
      # PLTE: dynamic palette of composed terrain colors
      assert <<plen::32, "PLTE", _plte::binary-size(plen), _crc2::32, _::binary>> = rest2
      assert rem(plen, 3) == 0
      assert plen >= 3 * 5 and plen <= 3 * 256
      # ends with IEND
      assert String.ends_with?(png, "IEND" <> <<174, 66, 96, 130>>)
    end

    test "IDAT decompresses to filter-prefixed scanlines with valid palette indices" do
      png = Texture.png(@seed, @frequency)
      {w, h} = Texture.dims()

      {pos, 4} = :binary.match(png, "IDAT")
      prefix = pos - 4
      <<_::binary-size(prefix), len::32, "IDAT", data::binary-size(len), _::binary>> = png
      raw = :zlib.uncompress(data)

      assert byte_size(raw) == h * (w + 1)

      for row <- 0..(h - 1) do
        assert :binary.at(raw, row * (w + 1)) == 0
      end

      # spot-check some pixels are valid palette indices
      for i <- Enum.take_every(1..(byte_size(raw) - 1), 977) do
        assert :binary.at(raw, i) < 64
      end
    end

    test "is cached and deterministic" do
      assert Texture.png(@seed, @frequency) == Texture.png(@seed, @frequency)
    end

    test "cloud_puffs are on-sphere, bounded, deterministic, seed-dependent" do
      puffs = Texture.cloud_puffs(@seed)

      assert puffs != []

      for [x, y, z, r, d] <- puffs do
        # unit-sphere center
        assert_in_delta x * x + y * y + z * z, 1.0, 0.01
        assert r >= 0.045 and r <= 0.121
        assert d >= 0.0 and d <= 1.0
      end

      assert Texture.cloud_puffs(@seed) == puffs
      refute Texture.cloud_puffs(@seed + 1) == puffs
    end

    test "some seed produces storm-density puffs" do
      assert Enum.any?(0..40, fn s ->
               Enum.any?(Texture.cloud_puffs(@seed + s), fn [_, _, _, _, d] -> d > 0.72 end)
             end)
    end

    test "different seeds give different textures" do
      refute Texture.png(@seed, @frequency) == Texture.png(@seed + 1, @frequency)
    end
  end
end
