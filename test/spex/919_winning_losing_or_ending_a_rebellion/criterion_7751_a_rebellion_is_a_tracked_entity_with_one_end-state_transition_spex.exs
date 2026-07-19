defmodule BrokenOathsSpex.Story919.Criterion7751Spex do
  @moduledoc """
  Story 919 — Winning, Losing, or Ending a Rebellion
  Criterion 7751 — "A Rebellion is a persisted first-class entity with a
  status of active, independence_won, crushed, or peace. It is created
  active by a declaration of independence (story 915) and transitions
  exactly once to one of the three ended statuses."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2 —
  first-class Rebellion").

  `BrokenOaths.Game.Rebellion` does not exist yet — there is no
  `lib/broken_oaths/game/rebellion.ex`, no `declare_independence`
  context function, and no `handle_event/3` clause for it anywhere in
  `GameLive.Play`. This criterion's own dependency, story 915
  (Declare Independence), is a SIBLING requirement in this same batch
  and hasn't shipped either — every action below is driven through
  `attempt_event/3` (the story 908 pattern), which survives calling an
  event with no matching `handle_event` clause without crashing the
  test.

  ## New judgment calls this criterion introduces

  1. **`"declare_independence"`** — fired with no params on the
     VASSAL's own `play_live`. Mirrors `"answer_levy"`'s own "a
     player has at most one lord, so no target disambiguation is
     needed" reasoning (story 908).
  2. **`data-test="rebellion-status"`** — a new status badge, mirroring
     the `vassal-status`/`city-status`/`levy-status` convention every
     prior story in this batch already established for a persisted
     relationship's own current state. Rendered on the REBEL's own
     view (unscoped — a player has at most one active rebellion), and
     nested inside the former lord's own `[data-test='vassal-row-ID']`
     as `[data-test='rebellion-status']` (the same dual-view placement
     `levy-status` already uses).

  ## Why this scenario drives ONE concrete resolution path

  The criterion's own "When" ("the rebellion later resolves") is
  deliberately generic — it is the umbrella invariant that holds across
  ALL THREE endings, each of which gets its own dedicated criterion
  (7752 independence_won, 7753 crushed, 7754 peace). This scenario
  drives the CRUSHED path specifically, because it is the only ending
  reachable through mechanics that are ALREADY real (story 906 siege) —
  independence_won needs an N-turn hold counter and peace needs an
  offer/accept flow, neither of which exists at all yet even as a
  judgment call worth inventing twice. See criterion_7753's own
  moduledoc for the dedicated crushed-and-re-vassalized assertions;
  this file only asserts the GENERIC "transitions exactly once, never
  flips back" invariant.

  Since Wes's city never actually rises back to him (story 915 isn't
  built), Lord Mira's own siege attempt below has no real rival target
  to grind — the assertions are expected to fail today for exactly
  that reason.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a rebellion is a tracked entity with one end-state transition" do
    scenario "the rebellion's status settles once and never reverts to active" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes is Lord Mira's vassal, then declares independence, creating a Rebellion with status \"active\"",
             context do
        context = a_freshly_subjugated_vassal(context)

        attempt_event(context.other_play_live, "declare_independence", %{})

        {:ok, context}
      end

      when_ "the rebellion later resolves — Lord Mira besieges and retakes the contested city",
            context do
        target =
          adjacent_land_tile(context.world, context.other_city.tile_id, [context.my_lord.tile_id])

        stepped_off =
          march_to(context.play_live, context.world, context.user, context.my_lord, target)

        {retaken_lord, _city} =
          capture_city(
            context.play_live,
            context.world,
            context.user,
            stepped_off,
            context.other_user,
            context.other_city
          )

        {:ok, Map.put(context, :my_lord, retaken_lord)}
      end

      then_ "its status transitions exactly once to independence_won, crushed, or peace",
            context do
        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(fresh_wes_live, "[data-test='rebellion-status']", "crushed")
        {:ok, context}
      end

      then_ "it never flips back to active on a later turn", context do
        for _ <- 1..5, do: Fixtures.advance_turn(context.world)

        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        # Anchor: still reads the SAME ended value several turns later —
        # not merely "not active" (which an empty/absent badge would
        # also satisfy vacuously), but the identical settled status.
        assert has_element?(fresh_wes_live, "[data-test='rebellion-status']", "crushed")
        refute has_element?(fresh_wes_live, "[data-test='rebellion-status']", "active")

        {:ok, context}
      end
    end
  end
end
