defmodule BrokenOathsSpex.Story873.Criterion7417Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7417 — exactly one Lord and one Settler, on workable land, inside the claimed region.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "spawn delivers a lord and a settler on workable land" do
    scenario "the starting units are right" do
      given_ :a_world
      given_ :registered_player

      when_ "the player joins the world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "they own exactly one Lord and one Settler", context do
        units = Fixtures.player_units(context.world, context.user)
        assert length(units) == 2
        assert length(for u <- units, u.type == :lord, do: u) == 1
        assert length(for u <- units, u.type == :settler, do: u) == 1
        {:ok, context}
      end

      then_ "both units stand on workable land inside the claimed region", context do
        region = Fixtures.claimed_region(context.world, context.user)
        %{regions: regions} = Fixtures.region_partition(context.world)
        region_tiles = Map.fetch!(regions, region)

        for unit <- Fixtures.player_units(context.world, context.user) do
          assert unit.tile_id in region_tiles
          assert Fixtures.tile_class(context.world, unit.tile_id) == :land
        end

        {:ok, context}
      end
    end
  end
end
