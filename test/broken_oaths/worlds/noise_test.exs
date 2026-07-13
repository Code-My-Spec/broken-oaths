defmodule BrokenOaths.Worlds.NoiseTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.Noise

  describe "init/1" do
    test "returns a 512-element tuple" do
      perm = Noise.init(42)
      assert tuple_size(perm) == 512
    end

    test "all values are in 0..255" do
      perm = Noise.init(42)

      for i <- 0..511 do
        val = elem(perm, i)
        assert val >= 0 and val <= 255, "Value at #{i} was #{val}"
      end
    end

    test "is deterministic - same seed produces same table" do
      assert Noise.init(42) == Noise.init(42)
    end

    test "different seeds produce different tables" do
      refute Noise.init(42) == Noise.init(43)
    end

    test "second half mirrors first half (doubled permutation)" do
      perm = Noise.init(42)

      for i <- 0..255 do
        assert elem(perm, i) == elem(perm, i + 256)
      end
    end
  end

  describe "noise3d/4" do
    setup do
      %{perm: Noise.init(42)}
    end

    test "returns values in [0, 1]", %{perm: perm} do
      for x <- 0..10, y <- 0..10, z <- 0..10 do
        val = Noise.noise3d(perm, x * 0.17, y * 0.17, z * 0.17)

        assert val >= 0.0 and val <= 1.0,
               "noise3d(#{x * 0.17}, #{y * 0.17}, #{z * 0.17}) = #{val} is out of [0,1]"
      end
    end

    test "is deterministic", %{perm: perm} do
      assert Noise.noise3d(perm, 1.5, 2.3, 0.7) == Noise.noise3d(perm, 1.5, 2.3, 0.7)
    end

    test "varies with position", %{perm: perm} do
      values =
        for x <- 0..9 do
          Noise.noise3d(perm, x * 0.5, 0.25, 0.75)
        end

      assert length(Enum.uniq(values)) > 1
    end

    test "is continuous - nearby points have similar values", %{perm: perm} do
      base = Noise.noise3d(perm, 5.0, 5.0, 5.0)
      nearby = Noise.noise3d(perm, 5.001, 5.001, 5.001)
      assert abs(base - nearby) < 0.01
    end

    test "handles negative coordinates", %{perm: perm} do
      val = Noise.noise3d(perm, -3.5, -2.7, -0.9)
      assert val >= 0.0 and val <= 1.0
    end

    test "handles zero coordinates", %{perm: perm} do
      val = Noise.noise3d(perm, 0.0, 0.0, 0.0)
      assert val >= 0.0 and val <= 1.0
    end

    test "handles large coordinates", %{perm: perm} do
      val = Noise.noise3d(perm, 1000.0, 2000.0, 3000.0)
      assert val >= 0.0 and val <= 1.0
    end
  end

  describe "fbm3d/4" do
    setup do
      %{perm: Noise.init(42)}
    end

    test "returns values in [0, 1]", %{perm: perm} do
      for x <- 0..5, y <- 0..5, z <- 0..5 do
        val = Noise.fbm3d(perm, x * 0.3, y * 0.3, z * 0.3)
        assert val >= 0.0 and val <= 1.0
      end
    end

    test "is deterministic", %{perm: perm} do
      assert Noise.fbm3d(perm, 1.5, 2.3, 0.7) == Noise.fbm3d(perm, 1.5, 2.3, 0.7)
    end

    test "produces variety across unit-sphere sample points", %{perm: perm} do
      # Sample points spread over the unit sphere, scaled like globe terrain
      scale = 2.2

      values =
        for i <- 0..17, j <- 0..17 do
          theta = i / 17 * :math.pi()
          phi = j / 17 * 2 * :math.pi()
          x = :math.sin(theta) * :math.cos(phi)
          y = :math.sin(theta) * :math.sin(phi)
          z = :math.cos(theta)
          Noise.fbm3d(perm, x * scale, y * scale, z * scale, 6)
        end

      min_val = Enum.min(values)
      max_val = Enum.max(values)

      assert max_val - min_val > 0.3,
             "3D FBM range too narrow over sphere: #{min_val}..#{max_val}"
    end
  end
end
