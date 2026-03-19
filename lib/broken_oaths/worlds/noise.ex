defmodule BrokenOaths.Worlds.Noise do
  @moduledoc """
  2D Perlin noise implementation for procedural terrain generation.
  Uses a seeded permutation table for deterministic output.
  """
  import Bitwise

  @doc """
  Initialize a permutation table from a seed.
  Returns a 512-element tuple (256 values doubled for overflow-safe indexing).
  """
  def init(seed) do
    :rand.seed(:exsss, {seed, seed * 7 + 13, seed * 31 + 97})
    base = Enum.to_list(0..255) |> Enum.shuffle()
    (base ++ base) |> List.to_tuple()
  end

  @doc """
  2D Perlin noise at coordinates (x, y). Returns a value in [0.0, 1.0].
  """
  def noise2d(perm, x, y) do
    x = x * 1.0
    y = y * 1.0

    xi = trunc(Float.floor(x)) &&& 255
    yi = trunc(Float.floor(y)) &&& 255

    xf = x - Float.floor(x)
    yf = y - Float.floor(y)

    u = fade(xf)
    v = fade(yf)

    a = elem(perm, xi) + yi
    aa = elem(perm, a)
    ab = elem(perm, a + 1)
    b = elem(perm, xi + 1) + yi
    ba = elem(perm, b)
    bb = elem(perm, b + 1)

    x1 = lerp(grad2d(aa, xf, yf), grad2d(ba, xf - 1.0, yf), u)
    x2 = lerp(grad2d(ab, xf, yf - 1.0), grad2d(bb, xf - 1.0, yf - 1.0), u)

    result = lerp(x1, x2, v)
    # Normalize from approximately [-1, 1] to [0, 1]
    min(1.0, max(0.0, (result + 1.0) / 2.0))
  end

  @doc """
  Fractal Brownian Motion - multiple octaves of noise layered together.
  Produces more natural-looking terrain with detail at multiple scales.
  """
  def fbm(perm, x, y, octaves \\ 6, lacunarity \\ 2.0, persistence \\ 0.5) do
    {total, _, max_val} =
      Enum.reduce(0..(octaves - 1), {0.0, 1.0, 0.0}, fn i, {total, amplitude, max_val} ->
        frequency = :math.pow(lacunarity, i)
        val = noise2d(perm, x * frequency, y * frequency)
        {total + val * amplitude, amplitude * persistence, max_val + amplitude}
      end)

    total / max_val
  end

  # Smoothstep fade curve: 6t^5 - 15t^4 + 10t^3
  defp fade(t), do: t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

  # Linear interpolation
  defp lerp(a, b, t), do: a + t * (b - a)

  # 2D gradient using 4 directions
  defp grad2d(hash, x, y) do
    case hash &&& 3 do
      0 -> x + y
      1 -> -x + y
      2 -> x - y
      3 -> -x - y
    end
  end
end
