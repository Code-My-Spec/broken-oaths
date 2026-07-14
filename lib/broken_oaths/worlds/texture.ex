defmodule BrokenOaths.Worlds.Texture do
  @moduledoc """
  Bakes a world into an equirectangular PNG — the far-zoom globe impostor.

  Every texture pixel is colored by its nearest REAL tile, so the genuine
  hex/pentagon pattern is baked in (fuzzily, at texture resolution). The
  client warps this image into an orthographic disc on a canvas when the
  view is too far out for tiles to be a usable game board; actual tile divs
  only exist near the surface.

  Two cached layers:
    * pixel → tile-id index: depends only on (frequency, dims); an
      `:atomics` array in `:persistent_term`, built once per node.
    * the PNG itself: depends on (seed, frequency, dims); ~100KB palette
      PNG in `:persistent_term`. Regenerating a world leaks the previous
      seed's entry until restart — acceptable at this size.
  """

  alias BrokenOaths.Worlds.{Generator, Globe}

  # Bump when the index/png layout OR palette changes (persistent_term
  # survives reloads, and browsers cache the PNGs as immutable).
  @cache_version 3

  @default_dims {2048, 1024}

  # Must cover every terrain atom Generator can produce; order = palette index.
  @palette [
    ocean: {0x1E, 0x3A, 0x8A},
    shallow_water: {0x3B, 0x82, 0xF6},
    beach: {0xFB, 0xBF, 0x24},
    grassland: {0x22, 0xC5, 0x5E},
    plains: {0x84, 0xCC, 0x16},
    forest: {0x15, 0x80, 0x3D},
    hills: {0x92, 0x40, 0x0E},
    mountains: {0x52, 0x52, 0x52},
    tundra: {0x8D, 0x9B, 0x8A},
    snow: {0xE6, 0xEC, 0xF2},
    jungle: {0x06, 0x5F, 0x46},
    swamp: {0x3F, 0x62, 0x12},
    desert: {0xD9, 0xC2, 0x6B}
  ]

  @doc """
  Texture dimensions {w, h} for a detail level; overridable for tests via
  config. Level 1 is full size, level 0 half — a tiny first-paint texture
  the client swaps out once level 1 arrives.
  """
  def dims(level \\ 1)

  def dims(1), do: Application.get_env(:broken_oaths, :texture_size, @default_dims)

  def dims(0) do
    {w, h} = dims(1)
    {max(div(w, 2), 2), max(div(h, 2), 2)}
  end

  @doc "Cache version — clients bust immutable texture URLs with it."
  def version, do: @cache_version

  @doc "Build (or fetch cached) the equirectangular PNG for a world."
  def png(seed, frequency, level \\ 1) do
    {w, h} = dims(level)
    key = {__MODULE__, @cache_version, :png, seed, frequency, w, h}

    case :persistent_term.get(key, nil) do
      nil ->
        png = build_png(seed, frequency, w, h)
        :persistent_term.put(key, png)
        png

      png ->
        png
    end
  end

  @doc "Pre-build the pixel indexes (used by the boot warm-up)."
  def warm(frequency) do
    for level <- [0, 1] do
      {w, h} = dims(level)
      index(frequency, w, h)
    end

    :ok
  end

  @doc """
  Pixel → tile-id index for a frequency as an `:atomics` array (1-based,
  row-major). Built once per node and cached.
  """
  def index(frequency, w, h) do
    key = {__MODULE__, @cache_version, :index, frequency, w, h}

    case :persistent_term.get(key, nil) do
      nil ->
        ids = build_index(frequency, w, h)
        :persistent_term.put(key, ids)
        ids

      ids ->
        ids
    end
  end

  # -------------------------------------------------------------------
  # Index: nearest real tile per texture pixel
  # -------------------------------------------------------------------

  # For each tile, paint every pixel within ~1.35 tile-spacings of its
  # center, keeping the best (largest center·pixel dot product) per pixel.
  # Voronoi cells only reach ~0.62 spacings, so coverage is total and each
  # pixel ends up with its true nearest tile. Concurrent chunks may race on
  # a get/compare/put, worst case writing the 2nd-nearest tile to a boundary
  # pixel — visually indistinguishable, so no locking.
  defp build_index(frequency, w, h) do
    mesh = Globe.get(frequency)
    spacing = 1.1071487177940904 / frequency

    ids = :atomics.new(w * h, signed: false)
    dots = :atomics.new(w * h, signed: false)

    rows =
      List.to_tuple(
        for py <- 0..(h - 1) do
          lat = :math.pi() * (0.5 - (py + 0.5) / h)
          {:math.sin(lat), :math.cos(lat)}
        end
      )

    cols =
      List.to_tuple(
        for px <- 0..(w - 1) do
          lon = 2 * :math.pi() * ((px + 0.5) / w - 0.5)
          {:math.sin(lon), :math.cos(lon)}
        end
      )

    mesh.tiles
    |> Map.values()
    |> Enum.chunk_every(2048)
    |> Task.async_stream(
      fn tiles ->
        Enum.each(tiles, &paint_tile(&1, ids, dots, rows, cols, w, h, spacing))
      end,
      ordered: false,
      timeout: 120_000
    )
    |> Stream.run()

    ids
  end

  defp paint_tile(tile, ids, dots, rows, cols, w, h, spacing) do
    {cx, cy, cz} = tile.center
    lat = :math.asin(max(-1.0, min(1.0, cz)))
    lon = :math.atan2(cy, cx)
    reach = spacing * 1.35

    py_min = max(trunc((0.5 - (lat + reach) / :math.pi()) * h), 0)
    py_max = min(trunc((0.5 - (lat - reach) / :math.pi()) * h) + 1, h - 1)

    coslat = :math.cos(lat)

    {px_from, px_to} =
      if coslat < 0.1 or abs(lat) + reach > :math.pi() / 2 - 0.05 do
        # Pole neighborhood: longitude is degenerate, take full rows
        {0, w - 1}
      else
        base = trunc((lon / (2 * :math.pi()) + 0.5) * w)
        half = trunc(reach / coslat / (2 * :math.pi()) * w) + 1
        {base - half, base + half}
      end

    tile_id = tile.id

    for py <- py_min..py_max//1 do
      {slat, clat} = elem(rows, py)
      row_base = py * w

      for pxr <- px_from..px_to//1 do
        px = rem(rem(pxr, w) + w, w)
        {slon, clon} = elem(cols, px)
        dot = clat * clon * cx + clat * slon * cy + slat * cz
        score = trunc(dot * 1_000_000_000)

        if score > 0 do
          i = row_base + px + 1

          if score > :atomics.get(dots, i) do
            :atomics.put(dots, i, score)
            :atomics.put(ids, i, tile_id)
          end
        end
      end
    end

    :ok
  end

  # -------------------------------------------------------------------
  # PNG (palette / color type 3, hand-assembled)
  # -------------------------------------------------------------------

  defp build_png(seed, frequency, w, h) do
    ids = index(frequency, w, h)
    terrain_map = Generator.generate_terrain_map(seed, Globe.get(frequency))
    n = Globe.tile_count(frequency)

    # tile id -> palette index, as a flat binary for O(1) lookup
    tile_pal =
      for id <- 0..(n - 1), into: <<>> do
        <<palette_index(Map.fetch!(terrain_map, id))>>
      end

    raw =
      for py <- 0..(h - 1), into: <<>> do
        row_base = py * w

        row =
          for px <- 0..(w - 1), into: <<>> do
            tile = :atomics.get(ids, row_base + px + 1)
            <<:binary.at(tile_pal, tile)>>
          end

        # filter byte 0 (None) + scanline
        <<0>> <> row
      end

    plte =
      for {_terrain, {r, g, b}} <- @palette, into: <<>> do
        <<r, g, b>>
      end

    ihdr = <<w::32, h::32, 8, 3, 0, 0, 0>>

    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      chunk("IHDR", ihdr) <>
      chunk("PLTE", plte) <>
      chunk("IDAT", :zlib.compress(raw)) <>
      chunk("IEND", <<>>)
  end

  defp chunk(type, data) do
    payload = type <> data
    <<byte_size(data)::32>> <> payload <> <<:erlang.crc32(payload)::32>>
  end

  defp palette_index(terrain) do
    Enum.find_index(@palette, fn {t, _} -> t == terrain end) ||
      raise "no palette color for terrain #{inspect(terrain)}"
  end
end
