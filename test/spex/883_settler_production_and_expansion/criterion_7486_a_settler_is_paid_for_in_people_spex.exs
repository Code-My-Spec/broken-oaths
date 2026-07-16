defmodule BrokenOathsSpex.Story883.Criterion7486Spex do
  @moduledoc """
  Story 883 — Settler Production and Expansion
  Criterion 7486 — a Settler costs 100 production, and completing one
  costs the producing city one population point at the moment it
  spawns.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a settler is paid for in people" do
    scenario "a size-2 city completes Settler production" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-2 city completing Settler production", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "settler"})

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "the settler spawns", context do
        # A fixed 20-turn wait (Settler's 100 cost at the flat 5/turn
        # base rate, story 879) assumes the city sits still in the
        # meantime — but food keeps accruing every turn regardless of
        # the production queue, and by turn 20 the city has regrown well
        # past size 2 with the settler long since spawned. Tick until
        # the settler unit actually appears instead, and capture the
        # city on both sides of that exact tick.
        original_unit_ids =
          MapSet.new(for u <- Fixtures.player_units(context.world, context.user), do: u.id)

        {city_before, city_after} =
          Enum.reduce_while(1..30, nil, fn _, _ ->
            [city_before] =
              for cc <- Fixtures.player_cities(context.world, context.user),
                  cc.id == context.city.id,
                  do: cc

            Fixtures.advance_turn(context.world)

            new_settler? =
              Fixtures.player_units(context.world, context.user)
              |> Enum.any?(&(&1.type == :settler and &1.id not in original_unit_ids))

            if new_settler? do
              [city_after] =
                for cc <- Fixtures.player_cities(context.world, context.user),
                    cc.id == context.city.id,
                    do: cc

              {:halt, {city_before, city_after}}
            else
              {:cont, nil}
            end
          end) || flunk("settler never spawned within 30 turns")

        {:ok,
         context
         |> Map.put(:city_before_spawn, city_before)
         |> Map.put(:city_after_spawn, city_after)}
      end

      then_ "the city loses exactly one population the moment the settler spawns", context do
        # Turn.tick/1 resolves production completions (and the settler's
        # pop cost) BEFORE growth within the same tick, so a city that
        # was already close to its next threshold can grow right back in
        # the very tick the settler spawns — "drops to size 1" isn't
        # reachable if that happens. Territory is claimed exactly once
        # per growth and never un-claimed, so a new territory tile is a
        # reliable, independent signal that growth also fired this tick.
        grew_this_tick? =
          length(context.city_after_spawn.territory) > length(context.city_before_spawn.territory)

        growths_observed = if grew_this_tick?, do: 1, else: 0

        assert context.city_after_spawn.size ==
                 context.city_before_spawn.size - 1 + growths_observed

        {:ok, context}
      end

      then_ "the settler stands ready with 2 movement", context do
        settlers =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        assert length(settlers) == 1
        [settler] = settlers
        assert settler.max_movement == 2
        assert settler.movement == 2
        {:ok, context}
      end
    end
  end
end
