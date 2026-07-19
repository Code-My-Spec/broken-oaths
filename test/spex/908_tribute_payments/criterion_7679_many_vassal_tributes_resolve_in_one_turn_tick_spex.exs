defmodule BrokenOathsSpex.Story908.Criterion7679Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7679 — tribute "must scale to many concurrent vassal
  relationships per world"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story
  description) — a lord with SEVERAL vassals gets every one of their
  tributes correctly resolved within the SAME single turn tick, not
  serialized across several boundaries or dropped for all but one.

  ## Reconciled against story 912's REAL gold-income mechanic
  (QA issue 589386f2)

  This spec used to declare a flat 12 gold/turn income for all three
  vassals (`Fixtures.set_player_gold_income/3`) — see
  `criterion_7674`'s own moduledoc for why that seam no longer feeds
  `apply_tribute/1` at all. Each vassal's captured city is instead
  grown to size 4 (`SharedGivens.grow_city_to/5`, `base_gold(4) = 3`
  deterministic regardless of terrain), and each one's own REAL
  per-turn income (`SharedGivens.real_gold_income/2`) is read
  individually right before the shared boundary — three DIFFERENT
  captured cities can easily have picked different worked-tile terrain
  (a Coast tile here, none there), so nothing assumes they all earn the
  same figure. The lord's own capital ALSO earns its own real income on
  this same boundary (they never go offline) — folded into their own
  expected total gain alongside all three tributes.

  Reuses `criterion_7677`'s own "world with room for three players"
  note — this criterion needs FOUR (one lord, three vassals), so it
  picks its own bigger deterministic world the same documented way
  (issue 7509b3e6: the shared `:a_world` fixture, seed 424242/frequency
  8, has exactly two spawnable regions).
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

      given_ "I hold three separate vassals, each with a real, grown per-turn gold income",
             context do
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
              march_to(
                vassal_context.play_live,
                context.world,
                context.user,
                my_lord,
                target,
                150
              )

            {my_lord, _broken_city} =
              capture_city(
                vassal_context.play_live,
                context.world,
                context.user,
                my_lord,
                other_user,
                vassal_context.other_city
              )

            # Story 909 postscript — see `criterion_7674`'s own
            # moduledoc: a LOGGED-IN vassal's own real income now
            # genuinely credits their own treasury too, which this
            # criterion's own tribute-only math isn't about.
            go_offline(vassal_context.other_play_live)

            %{user: other_user, conn: conn, city: vassal_context.other_city, my_lord: my_lord}
          end

        # Grow every vassal's captured city to size 4 AFTER all captures
        # complete — capture_city/march_to burn many real turn boundaries
        # between vassals, and both tribute AND growth correctly proceed
        # every one of them, so growing each one here simply continues
        # from wherever that already left it.
        for %{user: vassal_user, city: city} <- vassals do
          grow_city_to(context.world, vassal_user, city.id, 4)
        end

        {:ok, Map.put(context, :vassals, vassals)}
      end

      when_ "a single turn boundary passes", context do
        incomes =
          Map.new(context.vassals, fn %{user: u} -> {u.id, real_gold_income(context.world, u)} end)

        lord_income = real_gold_income(context.world, context.user)

        vassal_gold0 =
          Map.new(context.vassals, fn %{user: u} -> {u.id, Fixtures.gold(context.world, u)} end)

        lord_gold0 = Fixtures.gold(context.world, context.user)

        Fixtures.advance_turn(context.world)

        {:ok,
         context
         |> Map.put(:incomes, incomes)
         |> Map.put(:lord_income, lord_income)
         |> Map.put(:vassal_gold0, vassal_gold0)
         |> Map.put(:lord_gold0, lord_gold0)}
      end

      then_ "the lord collected exactly round(income x 25%) tribute from EACH of the three vassals",
            context do
        for %{my_lord: my_lord, city: city} <- context.vassals do
          assert my_lord.tile_id == city.tile_id
        end

        total_tribute =
          Enum.reduce(context.vassals, 0, fn %{user: vassal_user}, acc ->
            income = Map.fetch!(context.incomes, vassal_user.id)
            assert income >= 3

            expected_tribute = round(income * 0.25)
            assert expected_tribute > 0

            assert Fixtures.gold(context.world, vassal_user) ==
                     Map.fetch!(context.vassal_gold0, vassal_user.id) - expected_tribute

            acc + expected_tribute
          end)

        assert Fixtures.gold(context.world, context.user) ==
                 context.lord_gold0 + total_tribute + context.lord_income

        {:ok, context}
      end
    end
  end
end
