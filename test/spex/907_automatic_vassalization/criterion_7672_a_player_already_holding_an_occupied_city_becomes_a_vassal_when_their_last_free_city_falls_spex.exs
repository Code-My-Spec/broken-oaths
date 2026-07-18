defmodule BrokenOathsSpex.Story907.Criterion7672Spex do
  @moduledoc """
  Story 907 — Automatic Vassalization
  Criterion 7672 — a player who already has ONE city occupied (from an
  earlier capture) is not yet a vassal WHILE they still hold one free
  city (`criterion_7667`'s own rule) — but the moment that LAST free
  city also falls, vassalization fires, exactly like
  `criterion_7666`'s single-city case. "'Free city' = a city you own
  that no other player occupies... Vassalization fires at ZERO free
  cities. Multiple last-cities falling in one tick resolve in
  deterministic capture order, each firing its own last-free-city
  check" (`.code_my_spec/knowledge/feudal_vassalage_design.md`,
  "Round-5 decisions"). This criterion is that same captor taking BOTH
  of a two-city rival's cities in sequence — the first capture (of two)
  leaves them still free (`criterion_7667`'s own case); only the
  SECOND capture, their last, triggers the relationship.

  See `criterion_7666`'s own moduledoc for the shared `vassals-list`/
  `vassal-status` judgment calls, and `BrokenOathsSpex.Story906.
  Criterion7664Spex`'s own two-city setup this reuses.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a player already holding an occupied city becomes a vassal when their last free city falls" do
    scenario "capturing a rival's second (and last) city, after their first, triggers vassalization" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I already occupy one of the rival's two cities, and stand ready to take the other",
             context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        first_city = context.other_city

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.other_user),
                cc.id == first_city.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.other_play_live, "queue_production", %{
          "city_id" => to_string(first_city.id),
          "item" => "settler"
        })

        for _ <- 1..20, do: Fixtures.advance_turn(context.world)

        [new_settler] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        ring4 =
          Enum.reduce(1..4, {[first_city.tile_id], MapSet.new([first_city.tile_id])}, fn _,
                                                                                          {frontier,
                                                                                           seen} ->
            next =
              frontier
              |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
              |> Enum.uniq()
              |> Enum.reject(&MapSet.member?(seen, &1))
              |> Enum.filter(land?)

            {next, MapSet.union(seen, MapSet.new(next))}
          end)
          |> elem(0)

        [second_target | _] = ring4

        settler =
          march_to(
            context.other_play_live,
            context.world,
            context.other_user,
            new_settler,
            second_target
          )

        render_hook(context.other_play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        [second_city] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id != first_city.id,
              do: c

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        first_target =
          adjacent_land_tile(context.world, first_city.tile_id, [my_lord.tile_id])

        my_lord = march_to(context.play_live, context.world, context.user, my_lord, first_target)

        {my_lord, _broken_first} =
          capture_city(
            context.play_live,
            context.world,
            context.user,
            my_lord,
            context.other_user,
            first_city
          )

        assert my_lord.tile_id == first_city.tile_id
        refute has_element?(context.other_play_live, "[data-test='vassal-status']")

        second_target_adjacent =
          adjacent_land_tile(context.world, second_city.tile_id, [
            first_city.tile_id,
            my_lord.tile_id
          ])

        my_lord =
          march_to(context.play_live, context.world, context.user, my_lord, second_target_adjacent)

        grind_city(
          context.play_live,
          context.world,
          my_lord,
          context.other_user,
          second_city
        )

        context
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:second_city, second_city)
        |> then(&{:ok, &1})
      end

      when_ "I walk in and capture their second, and last, free city", context do
        my_lord =
          march_to(
            context.play_live,
            context.world,
            context.user,
            context.my_lord,
            context.second_city.tile_id
          )

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      then_ "the lord's own Vassals list gains the new vassal", context do
        assert context.my_lord.tile_id == context.second_city.tile_id

        assert has_element?(
                 context.play_live,
                 "[data-test='vassal-row-#{context.other_user.id}']",
                 context.other_user.email
               )

        {:ok, context}
      end

      then_ "the rival's own view shows they're now sworn to the lord", context do
        assert has_element?(
                 context.other_play_live,
                 "[data-test='vassal-status']",
                 context.user.email
               )

        {:ok, context}
      end
    end
  end
end
