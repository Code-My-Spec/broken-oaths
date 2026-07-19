defmodule BrokenOathsSpex.Story917.Criterion7749Spex do
  @moduledoc """
  Story 917 — Lord's Death — Seize the Moment
  Criterion 7749 — "The respawned heir resumes lordship over every
  vassal who did NOT win independence during the leaderless window;
  vassals who secured their freedom stay free. The dynasty endures,
  minus whoever slipped away — a lord's death is a succession crisis,
  not a permanent erasure."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story 917).

  Builds on `criterion_7748`'s own moduledoc for the "operationalizing
  the war's end" and flagged story-896-vs-917 heir-timing conflict —
  same reasoning applies here, not repeated. The NEW thing this
  criterion needs beyond `criterion_7744` (which already proves the
  oath survives the death itself, untouched, with zero heir
  involvement) is that lordship remains intact THROUGH a full
  leaderless-window-and-heir-respawn cycle for the vassals who stayed,
  while the one who left stays gone — proven here on the LORD's own
  Vassals panel (`vassal-row-\#{vassal_user_id}`), not merely on each
  vassal's own individual view.

  Three separate vassals under one lord, reusing
  `BrokenOathsSpex.Story908.Criterion7679Spex`'s own inline
  per-vassal subjugation loop ("world with room for four players").
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the heir keeps the vassals who never broke away", fail_on_error_logs: false do
    scenario "Ada and Bo are again vassals under the heir while Wes, who won independence, stays free" do
      given_ "a world with room for four players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 10}))}
      end

      given_(:registered_player)

      given_ "Lord Mira holds three vassals: Wes, Ada, and Bo", context do
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

            %{
              user: other_user,
              conn: conn,
              play_live: vassal_context.other_play_live,
              city: vassal_context.other_city,
              my_lord: my_lord
            }
          end

        {:ok, Map.put(context, :vassals, vassals)}
      end

      given_ "during the leaderless window Wes won independence while Ada and Bo never rebelled",
             context do
        [wes | _] = context.vassals
        [%{my_lord: last_lord}] = Enum.take(context.vassals, -1)

        # Guarantees Wes's own occupied city actually RISES on
        # declaration (`Resolution.city_rises?/4`, story 915) —
        # without this Mira sits at the untouched, high-Honor/low-
        # tribute defaults (`criterion_7735`'s own "just lord"
        # baseline), and a rebellion with an EMPTY `risen_city_ids`
        # never reaches `independence_won?/3` by mere waiting
        # (`Resolution`'s own moduledoc), so the heir this criterion
        # is about would never arrive. Same deterministic honor=0/
        # tribute=100% combo `a_freshly_subjugated_vassal_of_a_tyrant/1`
        # already establishes — scoped to Wes's OWN tribute rate only,
        # since Ada and Bo must stay ordinary (never-rebelling)
        # vassals throughout.
        :ok = Fixtures.set_player_honor(context.world, context.user, 0)

        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        render_hook(lord_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(wes.user.id),
          "rate" => "100"
        })

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

        attempt_event(wes.play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        # Ada and Bo deliberately take no action — never rebelling is the
        # point of this scenario.

        {:ok, Map.put(context, :dead_lord_id, last_lord.id)}
      end

      when_ "the heir respawns after the war ends", context do
        Enum.reduce_while(1..200, :ok, fn _, :ok ->
          heir_present? =
            context.world
            |> Fixtures.player_units(context.user)
            |> Enum.any?(&(&1.type == :lord and &1.id != context.dead_lord_id))

          if heir_present? do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "Ada and Bo are again vassals under the heir", context do
        [_wes, ada, bo] = context.vassals

        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        for %{user: kept_user} <- [ada, bo] do
          assert has_element?(lord_live, "[data-test='vassal-row-#{kept_user.id}']"),
                 "#{kept_user.email} never rebelled and should still be listed as an active vassal after the heir respawns"
        end

        for %{conn: kept_conn, user: kept_user} <- [ada, bo] do
          {:ok, kept_live, _html} = live(kept_conn, "/play/#{context.world.id}")

          assert has_element?(
                   kept_live,
                   "[data-test='vassal-status']",
                   "Sworn to #{context.user.email}"
                 ),
                 "#{kept_user.email} should still read sworn to the (now-heir) lord"
        end

        {:ok, context}
      end

      then_ "Wes remains free, so the dynasty continues having lost only Wes", context do
        [wes | _] = context.vassals

        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        refute has_element?(lord_live, "[data-test='vassal-row-#{wes.user.id}']"),
               "Wes won independence and should no longer be listed as one of Mira's vassals"

        {:ok, wes_live, _html} = live(wes.conn, "/play/#{context.world.id}")

        refute has_element?(wes_live, "[data-test='vassal-status']"),
               "Wes should read as free, not re-subjugated by the returning heir"

        {:ok, context}
      end
    end
  end
end
