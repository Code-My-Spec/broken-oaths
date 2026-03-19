defmodule BrokenOaths.Worlds.HexMathTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.HexMath

  describe "axial_to_pixel/3" do
    test "origin hex is at pixel (0, 0)" do
      assert {0.0, 0.0} = HexMath.axial_to_pixel(0, 0, 10)
    end

    test "moving right increases x by 1.5 * size" do
      {x, _y} = HexMath.axial_to_pixel(1, 0, 10)
      assert_in_delta x, 15.0, 0.001
    end

    test "moving down-right increases both x and y" do
      {x, y} = HexMath.axial_to_pixel(1, 0, 10)
      assert x > 0
      assert y > 0
    end

    test "moving down increases y by sqrt(3) * size" do
      {_x, y} = HexMath.axial_to_pixel(0, 1, 10)
      assert_in_delta y, 10 * :math.sqrt(3), 0.001
    end

    test "scales with hex size" do
      {x1, y1} = HexMath.axial_to_pixel(3, 4, 10)
      {x2, y2} = HexMath.axial_to_pixel(3, 4, 20)
      assert_in_delta x2, x1 * 2, 0.001
      assert_in_delta y2, y1 * 2, 0.001
    end
  end

  describe "neighbors/4" do
    test "interior hex has 6 neighbors" do
      neighbors = HexMath.neighbors(5, 5, 200, 150)
      assert length(neighbors) == 6
    end

    test "returns correct neighbor coordinates" do
      neighbors = HexMath.neighbors(5, 5, 200, 150)

      expected = [{6, 5}, {6, 4}, {5, 4}, {4, 5}, {4, 6}, {5, 6}]

      for n <- expected do
        assert n in neighbors, "Expected #{inspect(n)} in neighbors"
      end
    end

    test "wraps east-west at world boundary" do
      # Hex at right edge (q=199) should have neighbor at q=0
      neighbors = HexMath.neighbors(199, 5, 200, 150)
      q_values = Enum.map(neighbors, fn {q, _r} -> q end)
      assert 0 in q_values, "Right edge should wrap to q=0"
    end

    test "wraps west-east at world boundary" do
      # Hex at left edge (q=0) should have neighbor at q=199
      neighbors = HexMath.neighbors(0, 5, 200, 150)
      q_values = Enum.map(neighbors, fn {q, _r} -> q end)
      assert 199 in q_values, "Left edge should wrap to q=199"
    end

    test "clips at north boundary" do
      # Hex at top (r=0) loses neighbors with r < 0
      neighbors = HexMath.neighbors(5, 0, 200, 150)
      assert length(neighbors) < 6
      # All r values should be >= 0
      for {_q, r} <- neighbors do
        assert r >= 0
      end
    end

    test "clips at south boundary" do
      neighbors = HexMath.neighbors(5, 149, 200, 150)
      assert length(neighbors) < 6
      for {_q, r} <- neighbors do
        assert r < 150
      end
    end
  end

  describe "distance/4" do
    test "distance to self is 0" do
      assert HexMath.distance(5, 5, 5, 5) == 0
    end

    test "distance to adjacent hex is 1" do
      assert HexMath.distance(5, 5, 6, 5) == 1
      assert HexMath.distance(5, 5, 5, 6) == 1
      assert HexMath.distance(5, 5, 6, 4) == 1
    end

    test "distance is symmetric" do
      assert HexMath.distance(2, 3, 7, 8) == HexMath.distance(7, 8, 2, 3)
    end

    test "distance along q axis" do
      assert HexMath.distance(0, 0, 5, 0) == 5
    end

    test "distance along r axis" do
      assert HexMath.distance(0, 0, 0, 5) == 5
    end
  end

  describe "wrap_coordinates/4" do
    test "passes through valid coordinates unchanged" do
      assert {5, 5} = HexMath.wrap_coordinates(5, 5, 200, 150)
    end

    test "wraps q >= width" do
      assert {0, 5} = HexMath.wrap_coordinates(200, 5, 200, 150)
      assert {1, 5} = HexMath.wrap_coordinates(201, 5, 200, 150)
    end

    test "wraps negative q" do
      assert {199, 5} = HexMath.wrap_coordinates(-1, 5, 200, 150)
      assert {198, 5} = HexMath.wrap_coordinates(-2, 5, 200, 150)
    end

    test "returns nil for r < 0" do
      assert nil == HexMath.wrap_coordinates(5, -1, 200, 150)
    end

    test "returns nil for r >= height" do
      assert nil == HexMath.wrap_coordinates(5, 150, 200, 150)
    end

    test "r at boundaries is valid" do
      assert {5, 0} = HexMath.wrap_coordinates(5, 0, 200, 150)
      assert {5, 149} = HexMath.wrap_coordinates(5, 149, 200, 150)
    end
  end

  describe "hex dimensions" do
    test "hex_width is 2 * size" do
      assert HexMath.hex_width(10) == 20
    end

    test "hex_height is sqrt(3) * size" do
      assert_in_delta HexMath.hex_height(10), 17.32, 0.01
    end

    test "horizontal_spacing is 1.5 * size" do
      assert HexMath.horizontal_spacing(10) == 15.0
    end

    test "vertical_spacing is sqrt(3) * size" do
      assert_in_delta HexMath.vertical_spacing(10), 17.32, 0.01
    end
  end
end
