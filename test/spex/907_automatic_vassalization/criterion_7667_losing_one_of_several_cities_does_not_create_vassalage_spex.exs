defmodule BrokenOathsSpex.Story907.Criterion7667Spex do
  @moduledoc """
  Story 907 — Automatic Vassalization
  Criterion 7667 — capturing only ONE of a rival's several cities does
  NOT create a Vassalage relationship — they still have a free city
  left. "'Free city' = a city you own that no other player occupies...
  Vassalization fires at ZERO free cities"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-5
  decisions"). Mirrors `BrokenOathsSpex.Story906.Criterion7664Spex`'s
  own two-city setup, extended to check the VASSALAGE relationship
  itself (not just the per-city occupied badge that criterion already
  covers) never gets created.

  See `BrokenOathsSpex.Story907.Criterion7666Spex`'s own moduledoc for
  the shared `vassals-list`/`vassal-status` judgment calls.

  A second city is produced the same way
  `BrokenOathsSpex.Story883.Criterion7489Spex` already does.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "losing one of several cities does not create vassalage" do
    scenario "capturing one of two rival cities creates no Vassalage relationship" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the rival owns two cities, and I stand ready to capture only the first", context do
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

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, first_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        {:ok, context |> Map.put(:my_lord, my_lord) |> Map.put(:first_city, first_city)}
      end

      when_ "I capture only the first of the rival's two cities", context do
        {my_lord, _broken_city} =
          capture_city(
            context.play_live,
            context.world,
            context.user,
            context.my_lord,
            context.other_user,
            context.first_city
          )

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      then_ "the lord's own Vassals list stays empty", context do
        assert context.my_lord.tile_id == context.first_city.tile_id
        refute has_element?(context.play_live, "[data-test='vassals-list']")
        {:ok, context}
      end

      then_ "the rival's own view shows no Sworn-to badge, yet still renders their own city fine",
            context do
        refute has_element?(context.other_play_live, "[data-test='vassal-status']")

        [second_city] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id != context.first_city.id,
              do: c

        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(second_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-size']")
        {:ok, context}
      end
    end
  end
end
