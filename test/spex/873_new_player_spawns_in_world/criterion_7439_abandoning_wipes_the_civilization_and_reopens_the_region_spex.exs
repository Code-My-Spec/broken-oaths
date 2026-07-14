defmodule BrokenOathsSpex.Story873.Criterion7439Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7439 — abandoning demolishes everything the player owns and frees the region and a slot.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "abandoning wipes the civilization and reopens the region" do
    scenario "abandon with confirmation clears the board" do
      given_ :a_world
      given_ :registered_player

      given_ "the player has joined and holds a region", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        region = Fixtures.claimed_region(context.world, context.user)
        assert region != nil
        {:ok, Map.put(context, :region, region)}
      end

      when_ "they abandon the world and confirm the warning", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        play_live
        |> element("[data-test='abandon-world']")
        |> render_click()

        play_live
        |> element("[data-test='abandon-confirm']")
        |> render_click()

        {:ok, context}
      end

      then_ "everything they owned is gone and the region is claimable again", context do
        assert Fixtures.player_units(context.world, context.user) == []
        assert Fixtures.claimed_region(context.world, context.user) == nil
        assert context.region in Fixtures.spawnable_regions(context.world)
        {:ok, context}
      end

      then_ "the picker offers the world again — the slot is free", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")
        assert has_element?(join_live, "[data-test='join-world-#{context.world.id}']")
        {:ok, context}
      end
    end
  end
end
