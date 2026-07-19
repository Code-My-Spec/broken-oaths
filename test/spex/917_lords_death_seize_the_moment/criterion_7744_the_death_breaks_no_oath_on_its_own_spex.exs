defmodule BrokenOathsSpex.Story917.Criterion7744Spex do
  @moduledoc """
  Story 917 — Lord's Death — Seize the Moment
  Criterion 7744 — "A lord's death forces nothing: no oath auto-breaks
  and no vassal gains any mechanical buff. Each vassal independently
  CHOOSES whether to declare independence — those who prefer the
  arrangement, or fear the war, may stay vassals of the fallen lord's
  realm."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story 917).

  Reuses `BrokenOathsSpex.Story896.Criterion7573Spex`'s barbarian
  killing-blow setup (`Fixtures.set_unit_hp/3` +
  `Fixtures.resolve_barbarian_attack/3`) and
  `BrokenOathsSpex.SharedGivens.a_freshly_subjugated_vassal/1` /
  the inline two-vassal loop
  `BrokenOathsSpex.Story908.Criterion7679Spex` already established.

  ## "Neither vassal gains any... buff" — observable proxy

  Neither Oath Strain nor tribute rate has any OTHER lever in this
  scenario (no levy is issued, no tribute rate is changed), so this
  spec reads both `vassal-oath-strain` (`criterion_7678`'s own
  established regex-read pattern) and `my-tribute-rate` for BOTH
  vassals immediately after the kill and again after the next turn
  tick, asserting neither value moved. This is the narrowest
  observable stand-in for "no mechanical buff" available today — a
  discovered COMBAT buff (e.g. a free +attack) has no UI surface to
  read at all yet, so it is out of scope for this spec exactly the
  way `criterion_7725`'s own moduledoc scopes out army-size/city-rise
  assertions that belong to a different story/component.

  ## "One vassal declares independence... the other remains" —
  driven through `declare_independence`

  No `declare_independence` handler exists yet anywhere in `lib/`
  (`grep -rn declare_independence lib/` comes back empty, same fact
  `criterion_7725`'s own moduledoc already documents), so this is
  driven through `attempt_event/3` exactly like every other
  not-yet-built hook in this batch (`criterion_7677`/`7678`'s own
  `issue_levy`/`refuse_levy` precedent, back when THOSE didn't exist
  either). Expected to crash/no-op today — the RED signal this spec
  exists to produce.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  defp read_badge(live, selector) do
    html = render(live)

    case Regex.run(~r/data-test="#{selector}"[^>]*>([^<]+)</, html) do
      [_, text] -> String.trim(text)
      nil -> nil
    end
  end

  spex "the death breaks no oath on its own", fail_on_error_logs: false do
    scenario "neither vassal is auto-severed or buffed, and each independently chooses next turn" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)

      given_ "a lord with two vassals is set up", context do
        vassals =
          for _ <- 1..2 do
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

            %{
              user: other_user,
              conn: conn,
              play_live: vassal_context.play_live,
              city: vassal_context.other_city,
              my_lord: my_lord
            }
          end

        {:ok, Map.put(context, :vassals, vassals)}
      end

      given_ "a lord with two vassals is killed in combat", context do
        [%{my_lord: last_lord}] = Enum.take(context.vassals, -1)

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(last_lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == last_lord.tile_id))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)
        Fixtures.set_unit_hp(context.world, last_lord.id, 1)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, last_lord.id)

        baselines =
          for %{conn: vassal_conn} <- context.vassals do
            {:ok, vassal_live, _html} = live(vassal_conn, "/play/#{context.world.id}")

            %{
              strain: read_badge(vassal_live, "vassal-oath-strain"),
              tribute: read_badge(vassal_live, "my-tribute-rate")
            }
          end

        {:ok, Map.put(context, :baselines, baselines)}
      end

      when_ "the death is processed on the turn tick", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "neither vassal's Vassalage is severed automatically", context do
        for %{user: vassal_user, conn: vassal_conn} <- context.vassals do
          {:ok, vassal_live, _html} = live(vassal_conn, "/play/#{context.world.id}")

          assert has_element?(
                   vassal_live,
                   "[data-test='vassal-status']",
                   "Sworn to #{context.user.email}"
                 ),
                 "#{vassal_user.email} should still show as sworn to the fallen lord, oath never auto-breaks"
        end

        {:ok, context}
      end

      then_ "neither vassal gains any combat or economic buff from the death", context do
        for {%{conn: vassal_conn}, baseline} <- Enum.zip(context.vassals, context.baselines) do
          {:ok, vassal_live, _html} = live(vassal_conn, "/play/#{context.world.id}")

          after_strain = read_badge(vassal_live, "vassal-oath-strain")
          after_tribute = read_badge(vassal_live, "my-tribute-rate")

          assert after_strain == baseline.strain,
                 "Oath Strain moved from #{inspect(baseline.strain)} to #{inspect(after_strain)} with no levy/investment action taken"

          assert after_tribute == baseline.tribute,
                 "tribute rate moved from #{inspect(baseline.tribute)} to #{inspect(after_tribute)} with no lord action taken"
        end

        {:ok, context}
      end

      then_ "on the next turn one vassal declares independence while the other chooses to remain a vassal of the leaderless realm",
            context do
        [rebel, loyalist] = context.vassals

        Fixtures.advance_turn(context.world)

        attempt_event(rebel.play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, rebel_live, _html} = live(rebel.conn, "/play/#{context.world.id}")
        {:ok, loyalist_live, _html} = live(loyalist.conn, "/play/#{context.world.id}")

        refute has_element?(rebel_live, "[data-test='vassal-status']", "Sworn to #{context.user.email}"),
               "#{rebel.user.email} chose to declare independence and should no longer read sworn"

        assert has_element?(
                 loyalist_live,
                 "[data-test='vassal-status']",
                 "Sworn to #{context.user.email}"
               ),
               "#{loyalist.user.email} chose to stay and should still read sworn — declaring is a choice, not forced"

        {:ok, context}
      end
    end
  end
end
