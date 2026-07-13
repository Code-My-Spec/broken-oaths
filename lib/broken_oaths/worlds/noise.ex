defmodule BrokenOaths.Worlds.Noise do
  @moduledoc """
  3D Perlin noise for procedural terrain generation.
  Uses a seeded permutation table for deterministic output.

  Sampled at points on the unit sphere this yields seamless
  planetary terrain (no wrap seams, no polar pinching).
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
  3D Perlin noise at coordinates (x, y, z). Returns a value in [0.0, 1.0].
  """
  def noise3d(perm, x, y, z) do
    x = x * 1.0
    y = y * 1.0
    z = z * 1.0

    xi = trunc(Float.floor(x)) &&& 255
    yi = trunc(Float.floor(y)) &&& 255
    zi = trunc(Float.floor(z)) &&& 255

    xf = x - Float.floor(x)
    yf = y - Float.floor(y)
    zf = z - Float.floor(z)

    u = fade(xf)
    v = fade(yf)
    w = fade(zf)

    a = elem(perm, xi) + yi
    aa = elem(perm, a) + zi
    ab = elem(perm, a + 1) + zi
    b = elem(perm, xi + 1) + yi
    ba = elem(perm, b) + zi
    bb = elem(perm, b + 1) + zi

    x1 = lerp(grad3d(elem(perm, aa), xf, yf, zf), grad3d(elem(perm, ba), xf - 1.0, yf, zf), u)

    x2 =
      lerp(
        grad3d(elem(perm, ab), xf, yf - 1.0, zf),
        grad3d(elem(perm, bb), xf - 1.0, yf - 1.0, zf),
        u
      )

    y1 = lerp(x1, x2, v)

    x3 =
      lerp(
        grad3d(elem(perm, aa + 1), xf, yf, zf - 1.0),
        grad3d(elem(perm, ba + 1), xf - 1.0, yf, zf - 1.0),
        u
      )

    x4 =
      lerp(
        grad3d(elem(perm, ab + 1), xf, yf - 1.0, zf - 1.0),
        grad3d(elem(perm, bb + 1), xf - 1.0, yf - 1.0, zf - 1.0),
        u
      )

    y2 = lerp(x3, x4, v)

    result = lerp(y1, y2, w)
    # Normalize from approximately [-1, 1] to [0, 1]
    min(1.0, max(0.0, (result + 1.0) / 2.0))
  end

  @doc """
  3D Fractal Brownian Motion - multiple octaves of 3D noise layered together.
  Sample at unit-sphere points for seamless spherical terrain.
  """
  def fbm3d(perm, x, y, z, octaves \\ 6, lacunarity \\ 2.0, persistence \\ 0.5) do
    {total, _, max_val} =
      Enum.reduce(0..(octaves - 1), {0.0, 1.0, 0.0}, fn i, {total, amplitude, max_val} ->
        frequency = :math.pow(lacunarity, i)
        val = noise3d(perm, x * frequency, y * frequency, z * frequency)
        {total + val * amplitude, amplitude * persistence, max_val + amplitude}
      end)

    total / max_val
  end

  # Smoothstep fade curve: 6t^5 - 15t^4 + 10t^3
  defp fade(t), do: t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

  # Linear interpolation
  defp lerp(a, b, t), do: a + t * (b - a)

  # 3D gradient: Perlin's 12 edge-vector gradients (indices 12-15 repeat 4 of them)
  defp grad3d(hash, x, y, z) do
    case hash &&& 15 do
      0 -> x + y
      1 -> -x + y
      2 -> x - y
      3 -> -x - y
      4 -> x + z
      5 -> -x + z
      6 -> x - z
      7 -> -x - z
      8 -> y + z
      9 -> -y + z
      10 -> y - z
      11 -> -y - z
      12 -> y + x
      13 -> -y + z
      14 -> y - x
      15 -> -y - z
    end
  end
end
