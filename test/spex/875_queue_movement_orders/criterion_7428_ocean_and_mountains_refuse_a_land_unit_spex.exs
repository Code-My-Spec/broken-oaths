defmodule BrokenOathsSpex.Story875.Criterion7428Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7428 — impassable destinations are rejected at queue time with a reason.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "ocean and mountains refuse a land unit" do
    scenario "an impassable destination queues nothing" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      given_ "an impassable tile is known (water or mountain)", context do
        %{regions: regions, deep_ocean: deep_ocean} = Fixtures.region_partition(context.world)

        # Deep ocean may not exist at every seed; any non-:land tile is
        # equally impassable to a land unit.
        impassable =
          Enum.to_list(deep_ocean)
          |> Enum.concat(for {_id, tiles} <- regions, t <- tiles, do: t)
          |> Enum.find(&(Fixtures.tile_class(context.world, &1) != :land))

        [unit | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        {:ok, context |> Map.put(:unit, unit) |> Map.put(:impassable_tile, impassable)}
      end

      when_ "the player targets the impassable tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.unit.id,
          "to_tile" => context.impassable_tile
        })

        {:ok, context}
      end

      then_ "the order is rejected with a visible reason and the unit never moves", context do
        assert has_element?(context.play_live, "[data-test='order-error']")

        Fixtures.advance_turn(context.world)

        [unit] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.unit.id,
              do: u

        assert unit.tile_id == context.unit.tile_id
        {:ok, context}
      end
    end
  end
end
