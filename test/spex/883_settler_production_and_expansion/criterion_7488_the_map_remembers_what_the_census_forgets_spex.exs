defmodule BrokenOathsSpex.Story883.Criterion7488Spex do
  @moduledoc """
  Story 883 — Settler Production and Expansion
  Criterion 7488 — losing population to a settler un-works a tile but
  never un-claims territory; once claimed, a city's tiles are
  permanent.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the map remembers what the census forgets" do
    scenario "territory survives a settler's population cost" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-2 city that grew once and so claims eight tiles", context do
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

        [city] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
        territory_before = city.territory

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "settler"})

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:territory_before, territory_before)}
      end

      when_ "it completes a settler", context do
        # A fixed 20-turn wait assumes the city sits at exactly size 1
        # once the settler spawns — but food keeps accruing regardless
        # of the production queue, and by turn 20 the city has regrown
        # well past that. Tick until the settler unit actually appears,
        # and capture the city on both sides of that exact tick so the
        # "then_" steps below measure the CHANGE the settler caused, not
        # an absolute size/worked-tile count that a later regrowth can
        # move past.
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

      then_ "no claimed tile is ever lost", context do
        # The territory captured back when the city first reached size 2
        # remains a subset forever (territory is permanent, story 883) —
        # growth since then may have claimed MORE tiles, but never fewer.
        # Across the exact tick the settler spawns, territory can only
        # stay the same or gain one tile (a same-tick regrowth); it can
        # never shrink.
        assert length(context.territory_before) == 8

        assert MapSet.subset?(
                 MapSet.new(context.territory_before),
                 MapSet.new(context.city_before_spawn.territory)
               )

        assert length(context.city_after_spawn.territory) in
                 [length(context.city_before_spawn.territory),
                  length(context.city_before_spawn.territory) + 1]

        assert MapSet.subset?(
                 MapSet.new(context.city_before_spawn.territory),
                 MapSet.new(context.city_after_spawn.territory)
               )

        {:ok, context}
      end

      then_ "the settler's population cost un-works exactly one tile", context do
        # Territory only grows on a genuine growth event (`claim_growth_tile`
        # appends exactly one tile), so the territory-length delta across
        # this tick is a reliable, independent signal for whether a
        # same-tick regrowth also ran `assign_new_citizen` and re-worked a
        # tile — net worked_tiles change is -1 (the settler's cost) plus
        # that signal.
        growths_observed =
          length(context.city_after_spawn.territory) -
            length(context.city_before_spawn.territory)

        assert length(context.city_after_spawn.worked_tiles) ==
                 length(context.city_before_spawn.worked_tiles) - 1 + growths_observed

        {:ok, context}
      end
    end
  end
end
