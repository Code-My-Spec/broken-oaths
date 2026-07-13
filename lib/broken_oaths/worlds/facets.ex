defmodule BrokenOaths.Worlds.Facets do
  @moduledoc """
  Static CSS-3D placement data for globe tiles.

  CSS 3D transforms without a `perspective` property are an orthographic
  projection — the same projection the classic server renderer uses. Each
  tile becomes a div carrying a constant `matrix3d` that places it tangent
  to a nominal sphere of `r0` px, plus a constant tangent-plane `clip-path`.
  Rotating/zooming the globe is then a single transform update on the parent
  container, done client-side at 60fps with zero re-layout.

  Facets depend only on the mesh frequency, so they are computed once and
  cached in `:persistent_term` alongside the mesh.
  """

  alias BrokenOaths.Worlds.Globe

  # Nominal sphere radius (px) baked into the facet transforms; the client
  # container scales by S/r0. Larger r0 = sharper at deep zoom but more
  # texture memory (tiles rasterize at their r0 size).
  @r0 700

  def r0, do: @r0

  @doc "Facets for a frequency, building and caching on first use."
  def get(frequency) do
    case :persistent_term.get({__MODULE__, frequency}, nil) do
      nil ->
        facets = build(frequency)
        :persistent_term.put({__MODULE__, frequency}, facets)
        facets

      facets ->
        facets
    end
  end

  @doc "Build facets (uncached): one per tile, sorted by id."
  def build(frequency) do
    mesh = Globe.get(frequency)

    mesh.tiles
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.map(&facet/1)
  end

  # Element-local x maps to the tangent T, y to the bitangent B = N×T and
  # z to the outward normal N (so T×B = N keeps the facet front-facing for
  # backface-visibility culling). The div's local origin is the bounding-box
  # top-left, so the (u_min, v_min) offset is baked into the translation.
  defp facet(tile) do
    {_, _, nz} = n = tile.center
    ref = if abs(nz) > 0.9, do: {1.0, 0.0, 0.0}, else: {0.0, 0.0, 1.0}
    t = normalize(sub(ref, scale(n, dot(ref, n))))
    b = cross(n, t)

    uvw =
      Enum.map(tile.corners, fn c ->
        {dot(c, t) * @r0, dot(c, b) * @r0, dot(c, n) * @r0}
      end)

    us = Enum.map(uvw, &elem(&1, 0))
    vs = Enum.map(uvw, &elem(&1, 1))
    w_mean = Enum.sum(Enum.map(uvw, &elem(&1, 2))) / length(uvw)

    u_min = Enum.min(us)
    v_min = Enum.min(vs)
    bw = max(Float.ceil(Enum.max(us) - u_min), 1.0)
    bh = max(Float.ceil(Enum.max(vs) - v_min), 1.0)

    clip =
      "polygon(" <>
        Enum.map_join(uvw, ", ", fn {u, v, _} ->
          "#{pct((u - u_min) / bw)}% #{pct((v - v_min) / bh)}%"
        end) <> ")"

    {tx, ty, tz} = t
    {bx, by, bz} = b
    {nx, ny, nz} = n
    {px, py, pz} = add(add(scale(n, w_mean), scale(t, u_min)), scale(b, v_min))

    matrix =
      "matrix3d(#{f6(tx)},#{f6(ty)},#{f6(tz)},0," <>
        "#{f6(bx)},#{f6(by)},#{f6(bz)},0," <>
        "#{f6(nx)},#{f6(ny)},#{f6(nz)},0," <>
        "#{f6(px)},#{f6(py)},#{f6(pz)},1)"

    %{
      id: tile.id,
      w: trunc(bw),
      h: trunc(bh),
      clip: clip,
      matrix: matrix,
      pentagon?: tile.pentagon?
    }
  end

  defp f6(x), do: Float.round(x * 1.0, 6)

  defp pct(fraction) do
    fraction
    |> max(0.0)
    |> min(1.0)
    |> Kernel.*(100)
    |> Float.round(1)
  end

  defp normalize({x, y, z}) do
    len = :math.sqrt(x * x + y * y + z * z)
    {x / len, y / len, z / len}
  end

  defp sub({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}
  defp add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}
  defp scale({x, y, z}, s), do: {x * s, y * s, z * s}
  defp dot({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz

  defp cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}
end
