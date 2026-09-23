defmodule BrokenOathsSpex.Story39.Criterion3638Spex do
  @moduledoc """
  Story 39 — Fortify a unit for a defensive bonus
  Criterion 3638 — moving a fortified unit clears its Fortify stance.

  A fresh Warrior (`:defend` in its actions catalog,
  `BrokenOaths.Units.Actions.available/1`) is fortified, then queued to
  move one step to an adjacent open land tile. `queue_move` resolves
  immediately when movement remains (`BrokenOaths.Units.Unit.queue_move/4`'s
  own doc — no turn boundary needed), and `Simulation.Turn.Movement.
  apply_positions/3` resets `fortified_turns` to 0 the moment the unit's
  tile actually changes — so the stance should be gone by the time this
  `when_` returns, observed via the real UnitPanel: the `unit-fortified`
  badge disappears and the `fortify` button reappears (the two are
  mutually exclusive, `unit_panel.ex`'s own "never both at once" note).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "moving clears the fortified stance" do
    scenario "a fortified warrior moves to an adjacent open tile" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my fortified warrior stands beside an open land tile", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        occupied_tiles =
          for u <- Fixtures.player_units(context.world, context.user), u.id != warrior.id, do: u.tile_id

        [target_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == city.tile_id or &1 in occupied_tiles))

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})
        render_hook(play_live, "fortify", %{"unit_id" => to_string(warrior.id)})

        assert has_element?(play_live, "[data-test='unit-fortified']")

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:target_tile, target_tile)}
      end

      when_ "the player moves it to the adjacent tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.warrior.id),
          "to_tile" => context.target_tile
        })

        {:ok, context}
      end

      then_ "the unit has moved to the target tile", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.tile_id == context.target_tile
        {:ok, context}
      end

      then_ "its fortified stance is cleared, shown by the real panel", context do
        render_hook(context.play_live, "select_unit", %{
          "unit_id" => to_string(context.warrior.id)
        })

        refute has_element?(context.play_live, "[data-test='unit-fortified']")
        assert has_element?(context.play_live, "[data-test='fortify']")
        {:ok, context}
      end
    end
  end
end
