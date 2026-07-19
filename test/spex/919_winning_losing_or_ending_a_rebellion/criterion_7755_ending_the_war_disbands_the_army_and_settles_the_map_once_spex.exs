defmodule BrokenOathsSpex.Story919.Criterion7755Spex do
  @moduledoc """
  Story 919 — Winning, Losing, or Ending a Rebellion
  Criterion 7755 — "The moment a rebellion reaches any ended status,
  exactly once: the temporary rebellion army disbands, the contested
  cities settle to their final owners, the war state clears, and
  dependent effects fire — including the heir respawn for a leaderless
  realm (story 917)."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2").

  Reuses `"declare_independence"`/`data-test="rebellion-status"`
  (criterion_7751) and `data-test="city-status"` (criterion_7754).

  ## Flagged ambiguity: "any heir respawn fires" needs a leaderless realm

  Heir respawn (story 917) is a dependent effect of a rebellion ending
  ONLY when the former lord's own realm is actually leaderless at that
  moment ("the war ENDS (no active rebellion against the realm), an
  HEIR respawns... resuming lordship over every vassal who did NOT win
  independence"). The Gherkin's own Given for this criterion doesn't
  say whether Lord Mira is alive or dead — "any heir respawn fires" is
  only a meaningful, falsifiable claim if a leaderless realm actually
  exists to respawn into. This spec's own judgment call: kill Lord
  Mira's own lord unit (making Mira's realm leaderless) so the
  assertion has real teeth, using the SAME sanctioned, narrow-exception
  fixture combo `BrokenOathsSpex.Story896.Criterion7573Spex` already
  established for a lethal, RNG-independent kill
  (`Fixtures.spawn_barbarian/2` + `Fixtures.set_unit_hp/3` +
  `Fixtures.resolve_barbarian_attack/3`), and reuses THAT criterion's
  own `"game:lineage"` push-event judgment call as the "heir respawn"
  signal — the only "heir" signal that exists anywhere in this
  codebase today. Whether story 917 actually reuses `"game:lineage"` or
  introduces its own event is undecided; this is a documented guess,
  not a locked contract.

  ## Flagged ambiguity: disambiguating from the ALREADY-BUILT flat
  10-turn heir timer

  Story 896's own heir mechanic is UNCONDITIONAL today — it fires 10
  turns after ANY lord's death, with no awareness of an active
  rebellion. Story 917's whole point is to instead GATE that arrival on
  the war ending. If this spec killed Mira's lord and then waited
  exactly 10 turns for the rebellion to also resolve, a stray
  `"game:lineage"` push from the OLD, unconditional mechanic would
  land on the exact same tick as the war's own end — an indistinguishable
  false-positive risk (the assertion could pass for the wrong reason,
  with story 917 never actually gating anything). This spec instead
  holds the rebellion open for `@hold_turns = 20` turns — comfortably
  past turn 10 — and drains any stray `"game:lineage"` push that
  arrived from the OLD flat timer immediately before the war-ending
  tick, so the ONLY push counted for "heir respawn fires" is one
  produced strictly by THIS criterion's own war-end processing.

  ## "a temporary army of six warriors still fielded"

  Not hardcoded: fabricating an exact temp-army roster would pre-seed
  what story 915's own oath-strain-scaled spawn is supposed to produce.
  Instead this spec captures Wes's REAL unit roster (via the real
  `"game:units"` push) both before `declare_independence` and after the
  war ends, and asserts the roster returns to its pre-war size —
  "disbands" proven as a delta, not a fabricated headcount.

  ## Re-mounting after the crash

  Firing `"declare_independence"` (no `handle_event/3` clause exists
  yet) takes Wes's OWN `play_live` process down — `attempt_event/3`
  traps the exit in the TEST process so the test itself survives, but
  the crashed view's own pid is gone for good. Every later step re-
  mounts a fresh `other_play_live` (mirroring how every OTHER criterion
  in this file re-mounts before asserting rendered HTML) immediately
  after the attempt, so the `"game:units"`/`"game:lineage"` push
  listeners below have a live process to actually listen to.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  @hold_turns 20

  spex "ending the war disbands the army and settles the map, once" do
    scenario "once the rebellion resolves, the army disbands, the city settles, and the heir arrives — exactly once" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes's rebellion is active with a temporary army fielded, and Lord Mira's own realm is leaderless",
             context do
        context = a_freshly_subjugated_vassal_of_a_tyrant(context)

        # `Turn.resolve_heir/2`'s own real, already-shipped heir spawn
        # only ever lands at the fallen lord's own CAPITAL
        # (`capital_city/2` — their oldest owned city, by id); a lord
        # with NO city at all has nowhere for an heir to land, so
        # `resolve_heir/2` silently no-ops (deletes the pending entry,
        # pushes nothing). `a_freshly_subjugated_vassal_of_a_tyrant/1`
        # never gives Mira a city of her own (only Wes, the vassal,
        # founds one) — she needs one here so "Lord Mira's own realm is
        # leaderless" has a real capital for the heir below to actually
        # take.
        [my_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(my_settler.id)})

        wes_units_before = Fixtures.player_units(context.world, context.other_user)

        attempt_event(context.other_play_live, "declare_independence", %{})

        # `declare_independence` crashed Wes's own LiveView process
        # (no `handle_event/3` clause exists yet) — re-mount a fresh,
        # alive one for every later step to use.
        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        barbarian_target =
          adjacent_land_tile(context.world, context.my_lord.tile_id, [
            context.my_lord.tile_id,
            context.other_city.tile_id
          ])

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)
        Fixtures.set_unit_hp(context.world, context.my_lord.id, 1)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, context.my_lord.id)

        {:ok,
         context
         |> Map.put(:wes_units_before, wes_units_before)
         |> Map.put(:other_play_live, other_play_live)}
      end

      when_ "#{@hold_turns} turns pass and the rebellion's end is processed", context do
        for _ <- 1..(@hold_turns - 1), do: Fixtures.advance_turn(context.world)

        # Drain any stray push from the OLD, unconditional 10-turn heir
        # timer (already fired several turns ago) so only a FRESH push
        # produced by THIS final, war-ending tick counts below.
        drain_events(context.other_play_live, "game:units")
        drain_events(context.play_live, "game:lineage")

        Fixtures.advance_turn(context.world)

        units_at_end =
          case maybe_push_event(context.other_play_live, "game:units", 1000) do
            {:ok, %{units: units}} -> units
            :none -> :no_push_received
          end

        lineage_push = maybe_push_event(context.play_live, "game:lineage", 1000)

        {:ok,
         context
         |> Map.put(:units_at_end, units_at_end)
         |> Map.put(:lineage_push, lineage_push)}
      end

      then_ "the rebellion ends with status independence_won and the war state clears", context do
        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(fresh_wes_live, "[data-test='rebellion-status']", "independence_won")
        refute has_element?(fresh_wes_live, "[data-test='rebellion-status']", "active")

        {:ok, context}
      end

      then_ "the temporary rebellion army disbands", context do
        assert is_list(context.units_at_end), "expected a fresh \"game:units\" push after the final tick"
        assert length(context.units_at_end) == length(context.wes_units_before)

        {:ok, context}
      end

      then_ "the contested city settles to its final owner", context do
        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        render_hook(fresh_wes_live, "select_city", %{"city_id" => to_string(context.other_city.id)})

        assert has_element?(fresh_wes_live, "[data-test='city-size']")
        refute has_element?(fresh_wes_live, "[data-test='city-status']", "occupied")

        {:ok, context}
      end

      then_ "any heir respawn fires", context do
        assert {:ok, %{message: message}} = context.lineage_push
        assert is_binary(message) and message != ""

        {:ok, context}
      end

      then_ "all of these effects happen exactly once, not repeatedly on later ticks", context do
        drain_events(context.other_play_live, "game:units")
        drain_events(context.play_live, "game:lineage")

        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        # No SECOND lineage push — the heir already arrived once.
        assert maybe_push_event(context.play_live, "game:lineage", 500) == :none

        # The roster stays put — no repeat disband wiping units twice.
        units_again =
          case maybe_push_event(context.other_play_live, "game:units", 1000) do
            {:ok, %{units: units}} -> units
            :none -> :no_push_received
          end

        assert is_list(units_again)
        assert length(units_again) == length(context.units_at_end)

        {:ok, still_settled_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(
                 still_settled_wes_live,
                 "[data-test='rebellion-status']",
                 "independence_won"
               )

        {:ok, context}
      end
    end
  end
end
