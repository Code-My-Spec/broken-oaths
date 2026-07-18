defmodule BrokenOaths.Worlds.ResourcesTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Resources
  alias BrokenOaths.Worlds.World

  # A bespoke seed/frequency pair known to roll a healthy mix of
  # hills AND deep ocean (hills are naturally rare terrain — many
  # seeds roll none at all at small frequencies, the same reason
  # `criterion_7485`/`criterion_7484` reach for their own bespoke
  # seed 33 rather than the default `:a_world` fixture), so both the
  # Sheep/Stone (hills) and "ocean never carries a resource" cases
  # below have real coverage.
  @hilly_seed 7
  @frequency 30
  @total_tiles Globe.tile_count(@frequency)

  defp world(attrs \\ %{}) do
    Map.merge(
      %World{seed: @hilly_seed, frequency: @frequency, resource_density: :standard},
      attrs
    )
  end

  describe "at/2" do
    test "is deterministic for a given seed, frequency, and density" do
      w = world()
      first = for t <- 0..(@total_tiles - 1), into: %{}, do: {t, Resources.at(w, t)}
      second = for t <- 0..(@total_tiles - 1), into: %{}, do: {t, Resources.at(w, t)}

      assert first == second
      assert first |> Map.values() |> Enum.any?(&(&1 != nil))
    end

    test "never places a resource on non-land terrain" do
      w = world()

      for tile_id <- 0..(@total_tiles - 1), Resources.at(w, tile_id) != nil do
        assert Regions.tile_class(w, tile_id) == :land
      end
    end

    test "every placed resource sits on terrain its own kind allows" do
      w = world()

      placements =
        for tile_id <- 0..(@total_tiles - 1),
            resource = Resources.at(w, tile_id),
            resource != nil,
            do: {resource, Regions.terrain(w, tile_id)}

      assert placements != []
      assert Enum.all?(placements, fn {resource, terrain} -> eligible?(resource, terrain) end)
    end

    test "a hilly world actually rolls Sheep and/or Stone (both share the hills gate)" do
      w = world()

      hill_resources =
        for tile_id <- 0..(@total_tiles - 1),
            Regions.terrain(w, tile_id).relief == :hills,
            resource = Resources.at(w, tile_id),
            resource != nil,
            do: resource

      assert Enum.any?(hill_resources, &(&1 in [:sheep, :stone]))
    end

    test "dense places strictly more resources than sparse, for the same seed" do
      sparse = world(%{resource_density: :sparse})
      dense = world(%{resource_density: :dense})

      count = fn w -> Enum.count(0..(@total_tiles - 1), &(Resources.at(w, &1) != nil)) end

      assert count.(dense) > count.(sparse)
    end

    test "an ineligible tile (e.g. ocean) never carries a resource" do
      w = world()

      ocean_tile =
        Enum.find(0..(@total_tiles - 1), &(Regions.tile_class(w, &1) == :deep_ocean))

      refute is_nil(ocean_tile)
      assert Resources.at(w, ocean_tile) == nil
    end

    # Regression for the v0.2.1 playtest "resources missing" report
    # (issue 335f265c): the field symptom was "I've only seen wheat
    # resources... no Cattle, no Sheep, no Stone" on live, already-
    # running worlds. The placement math here was never actually wrong
    # (this whole describe block already covers it); the real failure
    # mode was a long-lived, hot-reloaded server serving an EARLIER,
    # incomplete `candidates/1` build out of the `:persistent_term`
    # cache forever, because nothing about a placement bugfix changes
    # a world's `{seed, frequency, density}` cache key (see
    # `Resources.@cache_version`'s own comment and the
    # `game-state-persistence` ADR). This locks in the actual
    # observable contract at real gameplay scale (`World.frequency`'s
    # own schema default, 54) across more than one seed, so a future
    # regression to "everything rolls the same kind" fails loudly.
    test "a real-scale world rolls more than one resource kind, not just wheat" do
      frequency = 54
      total = Globe.tile_count(frequency)

      for seed <- [7, 99, 20_260_718] do
        w = %World{seed: seed, frequency: frequency, resource_density: :standard}

        kinds =
          for tile_id <- 0..(total - 1),
              resource = Resources.at(w, tile_id),
              resource != nil,
              do: resource

        distinct_kinds = Enum.uniq(kinds)

        assert length(distinct_kinds) > 1,
               "seed #{seed}: only rolled #{inspect(distinct_kinds)} across the whole map"
      end
    end
  end

  defp eligible?(:cattle, %{base: :grassland, relief: :flat, feature: nil}), do: true
  defp eligible?(:cattle, _terrain), do: false

  defp eligible?(:wheat, %{base: :plains, relief: :flat, feature: nil}), do: true
  defp eligible?(:wheat, _terrain), do: false

  defp eligible?(:sheep, %{relief: :hills, feature: feature}), do: feature != :woods
  defp eligible?(:sheep, _terrain), do: false

  defp eligible?(:stone, %{relief: :hills, feature: feature}), do: feature != :woods
  defp eligible?(:stone, _terrain), do: false
end
