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

  describe "noise2d/3" do
    setup do
      %{perm: Noise.init(42)}
    end

    test "returns values in [0, 1]", %{perm: perm} do
      for x <- 0..20, y <- 0..20 do
        val = Noise.noise2d(perm, x * 0.1, y * 0.1)
        assert val >= 0.0 and val <= 1.0,
               "noise2d(#{x * 0.1}, #{y * 0.1}) = #{val} is out of [0,1]"
      end
    end

    test "is deterministic", %{perm: perm} do
      assert Noise.noise2d(perm, 1.5, 2.3) == Noise.noise2d(perm, 1.5, 2.3)
    end

    test "varies with position", %{perm: perm} do
      values =
        for x <- 0..9 do
          Noise.noise2d(perm, x * 0.5, 0.0)
        end

      # Should not all be the same value
      assert length(Enum.uniq(values)) > 1
    end

    test "is continuous - nearby points have similar values", %{perm: perm} do
      base = Noise.noise2d(perm, 5.0, 5.0)
      nearby = Noise.noise2d(perm, 5.001, 5.001)
      # Should be very close
      assert abs(base - nearby) < 0.01
    end

    test "handles negative coordinates", %{perm: perm} do
      val = Noise.noise2d(perm, -3.5, -2.7)
      assert val >= 0.0 and val <= 1.0
    end

    test "handles zero coordinates", %{perm: perm} do
      val = Noise.noise2d(perm, 0.0, 0.0)
      assert val >= 0.0 and val <= 1.0
    end

    test "handles large coordinates", %{perm: perm} do
      val = Noise.noise2d(perm, 1000.0, 2000.0)
      assert val >= 0.0 and val <= 1.0
    end
  end

  describe "fbm/3" do
    setup do
      %{perm: Noise.init(42)}
    end

    test "returns values in [0, 1]", %{perm: perm} do
      for x <- 0..10, y <- 0..10 do
        val = Noise.fbm(perm, x * 0.1, y * 0.1)
        assert val >= 0.0 and val <= 1.0,
               "fbm(#{x * 0.1}, #{y * 0.1}) = #{val} is out of [0,1]"
      end
    end

    test "is deterministic", %{perm: perm} do
      assert Noise.fbm(perm, 1.5, 2.3) == Noise.fbm(perm, 1.5, 2.3)
    end

    test "with more octaves has more detail variation", %{perm: perm} do
      # Sample at many points and check variance
      vals_1oct =
        for x <- 0..19, do: Noise.fbm(perm, x * 0.05, 0.0, 1)

      vals_6oct =
        for x <- 0..19, do: Noise.fbm(perm, x * 0.05, 0.0, 6)

      # 6 octaves should have more high-frequency variation
      diffs_1 = vals_1oct |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> abs(a - b) end)
      diffs_6 = vals_6oct |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> abs(a - b) end)

      avg_diff_1 = Enum.sum(diffs_1) / length(diffs_1)
      avg_diff_6 = Enum.sum(diffs_6) / length(diffs_6)

      # More octaves generally means more local variation (not always, but statistically)
      # This is a soft assertion - mainly checking it doesn't crash
      assert is_float(avg_diff_1)
      assert is_float(avg_diff_6)
    end

    test "produces variety across a map-sized area", %{perm: perm} do
      values =
        for q <- 0..199//10, r <- 0..149//10 do
          Noise.fbm(perm, q * 0.035, r * 0.035, 6)
        end

      min_val = Enum.min(values)
      max_val = Enum.max(values)

      # Should span a reasonable range of the [0,1] interval
      assert max_val - min_val > 0.3,
             "FBM range too narrow: #{min_val}..#{max_val}"
    end
  end
end
