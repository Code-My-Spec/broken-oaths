defmodule BrokenOathsSpex.Story893.Criterion7557Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7557 — defeating a barbarian pays the player a 10-gold
  bounty (per stone_age.md §3.2, "10 gold per kill").

  Barbarian-fixture note: see criterion 7551's moduledoc — this uses a
  REAL camp-spawned warrior, one of the 1-2 camps that spawn already
  inside the player's own territory (criterion 7543), attacked via the
  same "attack" event story 891 (`Game.Combat`) drives player-initiated
  combat through.

  The "attack" event has no handler yet (story 891 is unimplemented
  too), so calling it crashes the LiveView exactly as documented in
  criterion 7538's moduledoc (story 891) — this spec reuses that exact
  `attempt_attack/3` crash-safe wrapper and `fail_on_error_logs: false`
  so the RED here is a clean assertion failure, not an uncaught
  process EXIT taking the whole run down.

  KNOWN LIMITATION (statistical): barbarian warriors have no
  documented test-only HP-setting escape hatch the way
  `Fixtures.set_unit_hp/3` gives player units (story 881's healing
  criteria) — that fixture targets `Game.Unit` records, and barbarian
  warriors are explicitly NOT `Game.Unit` rows (see criterion 7533's
  moduledoc, story 891). Per the story text, barbarian warriors
  (15/15/120) are deliberately stronger than a lone Stone Age warrior
  (10/10/100) — "players lose 1v1" — so this spec throws two
  lord-boosted warriors (each getting the +2 aura, per criterion 7541)
  at a single barbarian across several turn boundaries, giving enough
  combined hits (per criterion 7541's ~20-33 damage band) to clear 120
  HP with a comfortable margin. This is a best-effort, not a
  deterministic guarantee, the same caveat class already normalized by
  criterion 7541's own "KNOWN LIMITATION (statistical)" note.

  Gold is read from the rendered HTML badge (`[data-test='player-gold']`),
  the same surface and exact value criterion 7418 (story 873) already
  established for a fresh spawn's starting 50 gold — nothing in this
  Stone Age MVP spends gold on production (production costs are a
  separate "production points" currency), so 50 is still the correct
  pre-bounty anchor here.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the bounty", fail_on_error_logs: false do
    scenario "killing a barbarian warrior pays the player 10 gold" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, revealing a nearby barbarian camp",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [camp | _] = camps0
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)
         |> Map.put(:camp_warrior_baseline_ids, MapSet.new(camp.warriors, & &1.id))}
      end

      given_ "two of my warriors and my lord surround a barbarian warrior at the camp's doorstep",
             context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        for _ <- 1..30, do: Fixtures.advance_turn(context.world)

        [warrior1, warrior2 | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        doorsteps =
          context.world
          |> Fixtures.adjacent_tiles(context.camp_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.city.tile_id))

        [d1, d2, d3 | _] = doorsteps

        for {unit, target} <- [{warrior1, d1}, {warrior2, d2}, {lord, d3}] do
          render_hook(context.play_live, "queue_move", %{
            "unit_id" => to_string(unit.id),
            "to_tile" => target
          })
        end

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [w1] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == warrior1.id, do: u

          [w2] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == warrior2.id, do: u

          [l] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

          if w1.tile_id == d1 and w2.tile_id == d2 and l.tile_id == d3 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      given_ "a barbarian warrior has spawned at the camp, adjacent to my whole party", context do
        warrior =
          Enum.reduce_while(1..12, nil, fn _turn, _acc ->
            Fixtures.advance_turn(context.world)
            assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
            camp = Enum.find(camps, &(&1.id == context.camp_id))

            new_warrior =
              Enum.find(camp.warriors, &(&1.id not in context.camp_warrior_baseline_ids))

            if new_warrior, do: {:halt, new_warrior}, else: {:cont, nil}
          end)

        {:ok, Map.put(context, :barbarian_id, warrior.id)}
      end

      when_ "my warriors keep attacking it, turn after turn, until it falls", context do
        result =
          Enum.reduce_while(1..6, :attacking, fn _round, :attacking ->
            my_warriors =
              for u <- Fixtures.player_units(context.world, context.user),
                  u.type == :warrior,
                  do: u

            live_attackers = Enum.filter(my_warriors, &(&1.movement > 0))

            attack_results =
              for attacker <- live_attackers do
                attempt_attack(context.play_live, attacker.id, context.barbarian_id)
              end

            assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
            camp = Enum.find(camps, &(&1.id == context.camp_id))
            still_alive = Enum.any?(camp.warriors, &(&1.id == context.barbarian_id))

            cond do
              Enum.any?(attack_results, &(&1 == :crashed)) ->
                {:halt, :crashed}

              not still_alive ->
                {:halt, :dead}

              true ->
                Fixtures.advance_turn(context.world)
                {:cont, :attacking}
            end
          end)

        {:ok, Map.put(context, :fight_result, result)}
      end

      then_ "the barbarian is destroyed and the player is paid a 10-gold bounty", context do
        assert context.fight_result == :dead,
               "the fight never resolved cleanly (result: #{inspect(context.fight_result)}) — " <>
                 "either the \"attack\" event crashed (no handler implemented yet) or the barbarian outlasted the assault"

        assert has_element?(context.play_live, "[data-test='player-gold']", "60")
        {:ok, context}
      end
    end
  end

  # The "attack" event has no handler yet, so calling it crashes the
  # LiveView (`FunctionClauseError` in `handle_event/3`) — expected
  # until `Game.Combat` lands. That crash reaches this (linked) test
  # process as a genuine process EXIT signal, not a value `render_hook`
  # itself raises — plain `try/rescue`/`catch :exit` around the call
  # does not intercept it. Trapping exits around the call converts it
  # into an ordinary `{:EXIT, pid, reason}` message instead, so the RED
  # here is a clean assertion failure instead of an uncaught process
  # EXIT taking down the whole test. (Same helper as criterion 7538,
  # story 891.)
  defp attempt_attack(live_view, unit_id, target_unit_id) do
    original_trap = Process.flag(:trap_exit, true)

    result =
      try do
        render_hook(live_view, "attack", %{
          "unit_id" => to_string(unit_id),
          "target_unit_id" => to_string(target_unit_id)
        })

        :ok
      rescue
        _ -> :crashed
      catch
        :exit, _ -> :crashed
      end

    result =
      receive do
        {:EXIT, _pid, _reason} -> :crashed
      after
        100 -> result
      end

    Process.flag(:trap_exit, original_trap)
    result
  end
end
