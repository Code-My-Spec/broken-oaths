defmodule BrokenOathsSpex.Story908.Criterion7679Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7679 — tribute "must scale to many concurrent vassal
  relationships per world"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story
  description) — a lord with SEVERAL vassals gets every one of their
  tributes correctly resolved within the SAME single turn tick, not
  serialized across several boundaries or dropped for all but one.

  Reuses `criterion_7674`'s own gold-income-gap workaround
  (`Fixtures.set_player_gold/3`/`Fixtures.set_player_gold_income/3`)
  and `criterion_7677`'s own "world with room for three players" note
  — this criterion needs FOUR (one lord, three vassals), so it picks
  its own bigger deterministic world the same documented way (issue
  7509b3e6: the shared `:a_world` fixture, seed 424242/frequency 8, has
  exactly two spawnable regions).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "many vassal tributes resolve in one turn tick" do
    scenario "a lord with three vassals collects all three tributes in a single boundary" do
      given_ "a world with room for four players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 10}))}
      end

      given_(:registered_player)

      given_ "I hold three separate vassals, each earning their own gold income", context do
        vassals =
          for _ <- 1..3 do
            other_user = Fixtures.user_fixture()

            conn =
              Phoenix.ConnTest.build_conn()
              |> BrokenOathsTest.ConnCase.log_in_user(other_user)

            vassal_context =
              context
              |> Map.put(:other_user, other_user)
              |> Map.put(:other_conn, conn)
              |> join_and_found_rival_city()

            :ok = clear_all_camps(context.world)

            [my_lord] =
              for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

            target =
              adjacent_land_tile(
                context.world,
                vassal_context.other_city.tile_id,
                [my_lord.tile_id]
              )

            my_lord =
              march_to(vassal_context.play_live, context.world, context.user, my_lord, target, 150)

            {my_lord, _broken_city} =
              capture_city(
                vassal_context.play_live,
                context.world,
                context.user,
                my_lord,
                other_user,
                vassal_context.other_city
              )

            :ok = Fixtures.set_player_gold(context.world, other_user, 100)
            :ok = Fixtures.set_player_gold_income(context.world, other_user, 12)

            %{user: other_user, conn: conn, city: vassal_context.other_city, my_lord: my_lord}
          end

        lord_gold0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:vassals, vassals)
        |> Map.put(:lord_gold0, lord_gold0)
        |> then(&{:ok, &1})
      end

      when_ "a single turn boundary passes", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the lord collected exactly 3 gold tribute from EACH of the three vassals", context do
        for %{my_lord: my_lord, city: city} <- context.vassals do
          assert my_lord.tile_id == city.tile_id
        end

        for %{user: vassal_user} <- context.vassals do
          assert Fixtures.gold(context.world, vassal_user) == 97
        end

        assert Fixtures.gold(context.world, context.user) == context.lord_gold0 + 9
        {:ok, context}
      end
    end
  end
end
