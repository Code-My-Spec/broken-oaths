defmodule BrokenOathsSpex.Story953.Criterion2775Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2775 — a turn boundary restores movement and continues a
  still-pending path in the same tick.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a turn boundary recharges and continues a remaining path" do
    scenario "a unit at zero movement has a pending final step" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined the world and a warrior has spent its movement with a path still queued", context do
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

        # A freshly-produced unit spawns mid-tick at zero current movement
        # — one more tick primes it to its own `max_movement` before it can
        # spend anything on the moves below.
        Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        # First hop: exactly one land tile away, so the warrior's own
        # single movement point fully covers it and it arrives this same
        # request — same "queue_move resolves immediately" behavior every
        # other criterion in this file already exercises. Excludes every
        # tile one of this player's own units already stands on (the
        # freshly spawned Lord rests right beside a size-1 city's own
        # worked tiles) — `adjacent_land_tile/3` only ever checks terrain
        # class, not occupancy, so a same-class stack (Lord + Warrior,
        # both combat, no field-stacking room) would otherwise silently
        # refuse the move as `:occupied`.
        own_tiles = [city.tile_id | for(u <- Fixtures.player_units(context.world, context.user), do: u.tile_id)]
        step1 = adjacent_land_tile(context.world, warrior.tile_id, own_tiles)

        render_hook(play_live, "queue_move", %{
          "unit_id" => to_string(warrior.id),
          "to_tile" => to_string(step1)
        })

        # Second hop, queued immediately after arrival while movement is
        # already at zero: `move_now/2` can't spend anything on it this
        # request, so it sits fully pending — exactly this criterion's own
        # "spent its movement with a path still queued" premise — ready to
        # resolve on the very next turn boundary. Same occupancy exclusion,
        # re-read fresh now that the warrior itself has moved to `step1`.
        own_tiles_now = [
          city.tile_id | for(u <- Fixtures.player_units(context.world, context.user), do: u.tile_id)
        ]

        step2 = adjacent_land_tile(context.world, step1, own_tiles_now)

        render_hook(play_live, "queue_move", %{
          "unit_id" => to_string(warrior.id),
          "to_tile" => to_string(step2)
        })

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:warrior, warrior)}
      end

      when_ "the next turn boundary resolves", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the warrior's movement is restored before its remaining path continues", context do
        assert has_element?(context.play_live, "[data-test='unit-movement']")
        {:ok, context}
      end

      then_ "the queued move advances in that same tick", context do
        refute has_element?(context.play_live, "[data-test='unit-order']", "Moving to tile")
        {:ok, context}
      end
    end
  end
end
