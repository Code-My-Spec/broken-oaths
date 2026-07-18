defmodule BrokenOathsSpex.Story906.Criterion7664Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7664 — capturing ONE of a rival's several cities leaves
  them "free" overall: their remaining, untouched city stays un-marked,
  and the rival isn't vassalized. "'Free city' = a city you own that no
  other player occupies... Vassalization fires at ZERO free cities"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-5
  decisions"). This is `criterion_7665`'s own contrast: capturing a
  city when the owner has ANOTHER free one left behind does NOT trigger
  the last-free-city vassalization check that criterion exercises.

  See `criterion_7657`'s own moduledoc for the shared `city-status`
  badge/`grind_city/6` judgment calls. `criterion_7664` adds its own:
  a healthy, un-occupied city renders NO `city-status` badge at all
  (stated already in `criterion_7657`'s point 1) — this is the first
  criterion to actually rely on that absence as its own anchor,
  distinguishing "no badge" (free) from "occupied"/"broken" (not free).

  A second city is produced the same way
  `BrokenOathsSpex.Story883.Criterion7489Spex` already does: grow the
  first city to size 2, queue a Settler, march it 4+ hexes out, found.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "occupying a non-last city leaves the owner free" do
    scenario "capturing one of two rival cities leaves the untouched one free" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the rival owns two cities, and I've captured only the first", context do
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

        target = adjacent_land_tile(context.world, first_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        grind_city(context.play_live, context.world, my_lord, context.other_user, first_city)

        my_lord =
          march_to(context.play_live, context.world, context.user, my_lord, first_city.tile_id)

        context
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:first_city, first_city)
        |> Map.put(:second_city, second_city)
        |> then(&{:ok, &1})
      end

      when_ "the rival checks their own city list", context do
        {:ok, context}
      end

      then_ "the captured city reads occupied, but the untouched second city reads free",
            context do
        assert context.my_lord.tile_id == context.first_city.tile_id

        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.first_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-status']", "occupied")

        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.second_city.id)
        })

        refute has_element?(context.other_play_live, "[data-test='city-status']")
        {:ok, context}
      end

      then_ "the rival is not marked as anyone's vassal", context do
        refute has_element?(context.other_play_live, "[data-test='vassal-status']")
        {:ok, context}
      end
    end
  end
end
