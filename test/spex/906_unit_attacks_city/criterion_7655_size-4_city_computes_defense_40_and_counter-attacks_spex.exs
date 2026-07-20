defmodule BrokenOathsSpex.Story906.Criterion7655Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7655 — a size-4, undefended city's defensive strength is
  exactly `20 + 5×4 = 40` (`Game.CityDefense.defensive_strength/2`),
  and an assault on it still resolves a counter-attack computation
  (zero, since undefended — `Game.CityDefense.resolve_attack/4`'s own
  moduledoc: "an undefended city (empty garrison) counters for
  nothing").

  Already-implemented behavior — see `criterion_7652`'s own moduledoc
  for why city assault predates this story. `criterion_7656` is this
  criterion's own sibling/contrast: the SAME size-4 city, but garrisoned,
  showing the additive garrison bonus raises defense above this 40
  baseline.

  A player's Lord spawns on a DIFFERENT tile than their Settler
  (`BrokenOaths.Simulation.Spawner`'s own doc: "`settler_tile` is ... distinct
  from `lord_tile`"), so founding a city on the settler's tile and never
  moving the Lord onto it leaves the city genuinely ungarrisoned —
  `Game.CityDefense.military_garrison/2` finds nothing standing on the
  city's own tile.

  Growth to size 4 mirrors `BrokenOathsSpex.Story903.Criterion7636Spex`'s
  own "abundant food, wait up to 300 turns" idiom.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a size-4 city computes defense 40 and still resolves a counter" do
    scenario "an undefended size-4 rival city shows defense 40 and counters an assault for 0" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "an undefended rival city has grown to size 4, and my Lord stands adjacent", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        Enum.reduce_while(1..300, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.other_user),
                cc.id == context.other_city.id,
                do: cc

          if c.size >= 4 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      when_ "I order my Lord to attack the rival city", context do
        attempt_event(context.play_live, "attack", %{
          "unit_id" => to_string(context.my_lord.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "the rival's own city panel shows defense 40, and my Lord takes no counter damage",
            context do
        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-defense']", "40")

        assert_push_event(context.play_live, "game:combat", %{damage_taken: taken}, 500)
        assert taken == 0
        {:ok, context}
      end
    end
  end
end
