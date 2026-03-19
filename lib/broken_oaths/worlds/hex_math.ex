defmodule BrokenOaths.Worlds.HexMath do
  @moduledoc """
  Hex grid math for flat-top hexagons using axial coordinates (q, r).

  Reference: https://www.redblobgames.com/grids/hexagons/

  Flat-top hex layout:
    x = size * 3/2 * q
    y = size * (√3/2 * q + √3 * r)
  """

  @sqrt3 :math.sqrt(3)

  @doc "Convert axial (q, r) to pixel coordinates for flat-top hexagons."
  def axial_to_pixel(q, r, hex_size) do
    x = hex_size * 1.5 * q
    y = hex_size * (@sqrt3 / 2.0 * q + @sqrt3 * r)
    {x, y}
  end

  @doc "Get the 6 neighbors of a hex, handling cylindrical wrapping."
  def neighbors(q, r, world_width, world_height) do
    [{1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1}]
    |> Enum.map(fn {dq, dr} -> wrap_coordinates(q + dq, r + dr, world_width, world_height) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Distance between two hexes (cube coordinate manhattan distance / 2)."
  def distance(q1, r1, q2, r2) do
    s1 = -q1 - r1
    s2 = -q2 - r2
    div(abs(q1 - q2) + abs(r1 - r2) + abs(s1 - s2), 2)
  end

  @doc """
  Wrap coordinates for cylindrical topology.
  East-west: wraps around. North-south: hard boundaries.
  Returns {wrapped_q, r} or nil if r is out of bounds.
  """
  def wrap_coordinates(q, r, world_width, world_height) do
    wrapped_q = rem(rem(q, world_width) + world_width, world_width)

    if r >= 0 and r < world_height do
      {wrapped_q, r}
    else
      nil
    end
  end

  @doc "Hex width in pixels for a given circumradius size."
  def hex_width(size), do: size * 2

  @doc "Hex height in pixels for a given circumradius size."
  def hex_height(size), do: size * @sqrt3

  @doc "Horizontal spacing between hex centers."
  def horizontal_spacing(size), do: size * 1.5

  @doc "Vertical spacing between hex centers."
  def vertical_spacing(size), do: size * @sqrt3
end
