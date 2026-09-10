defmodule BrokenOathsSpex.Story953.Criterion2779Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2779 — movement recharges and pending movement resolves even
  on a tick that does not run economy phases.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a non-economy tick still recharges and resolves movement" do
    scenario "a unit has spent its movement with a remaining path on an off-economy tick" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and a warrior has a pending path at zero movement", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        :ok = clear_all_camps(context.world)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        step1 = adjacent_land_tile(context.world, warrior.tile_id)
        step2 = adjacent_land_tile(context.world, step1, [warrior.tile_id])

        render_hook(play_live, "queue_move", %{
          "unit_id" => to_string(warrior.id),
          "to_tile" => to_string(step2)
        })

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:warrior, warrior)}
      end

      when_ "a non-economy tick resolves", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "movement recharges and the pending order resolves despite skipped economy phases", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']")
        refute has_element?(context.play_live, "[data-test='order-error']")
        {:ok, context}
      end
    end
  end
end
