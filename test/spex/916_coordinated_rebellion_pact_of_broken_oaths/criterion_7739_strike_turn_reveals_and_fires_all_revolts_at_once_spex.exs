defmodule BrokenOathsSpex.Story916.Criterion7739Spex do
  @moduledoc """
  Story 916 — Coordinated Rebellion (Pact of Broken Oaths)
  Criterion 7739 — "At the strike turn all commitments reveal
  simultaneously and every committed conspirator declares independence
  together, each resolving its own city uprising and its own
  strain-sized rebellion army via story 915. Their power is numbers and
  the shared war breaking many oaths at once — there is no mechanical
  coordination bonus"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2 —
  first-class Rebellion, Pact-in-chat").

  See `BrokenOathsSpex.Story916.Criterion7737Spex`'s own moduledoc for
  the full assumed `RebellionPact` surface contract this spec drives.

  ## Judgment call: what "no coordination bonus" and "its own
  strain-sized army" mean for THIS spec

  Story 915 (Declare Independence) is ALSO not built yet
  (`grep -rn declare_independence lib/` comes back empty — confirmed
  the same way `BrokenOathsSpex.Story913.Criterion7725Spex`'s own
  moduledoc already documented). Whatever concrete shape a "temporary
  rebellion army" or "occupied-city uprising" takes is 915's own
  component to define and its own specs' job to encode in detail. This
  criterion's OWN, independently-testable claim — the one story 916
  actually owns — is narrower: (a) BOTH committed conspirators flip
  from "sworn vassal" to "declared independence" within the SAME single
  turn tick (simultaneity), and (b) the conspirator who never committed
  is UNAFFECTED (selectivity — the strike doesn't sweep in bystanders).
  This spec asserts exactly those two observable facts through each
  player's own `vassal-status`/new `rebellion-status` badges, and
  explicitly does NOT assert anything about rebellion army size, which
  cities rise, or any numeric "coordination bonus" — those belong to
  915's own specs and aren't independently observable through any
  surface today.

  ## Judgment call: "turn 50" as a RELATIVE, not absolute, boundary

  Same substitution rationale as `Criterion7737Spex`'s own moduledoc
  (point 1): subjugating three vassals via `subjugate/5` alone burns
  many dozens of real turn boundaries before any pact exists, so "turn
  50" can't mean "the world's turn counter literally reads 50" by the
  time a pact is ever opened. This spec advances exactly 49 further
  real turn boundaries as `given_` setup (still short of the strike),
  then a SINGLE 50th boundary as its own `when_` — the tick in which
  the strike is expected to fire — mirroring the gherkin's own "Given
  ... with strike turn 50 / When turn 50 processes" split precisely,
  just counted relative to pact formation instead of from world genesis.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "strike turn reveals and fires all revolts at once", fail_on_error_logs: false do
    scenario "Strike turn reveals and fires all revolts at once" do
      given_ "a world with room for four players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 10}))}
      end

      given_(:registered_player)
      given_(:three_vassals_of_one_lord)
      given_(:wes_opened_pact_inviting_ada_and_bo)

      given_ "Wes and Ada committed and Bo did not, with strike turn 50", context do
        {:ok, wes_live, _html} = live(context.wes.conn, "/play/#{context.world.id}")
        attempt_event(wes_live, "pact_commit", %{})

        {:ok, ada_live, _html} = live(context.ada.conn, "/play/#{context.world.id}")
        attempt_event(ada_live, "pact_commit", %{})

        # Bo neither commits nor declines — the gherkin's own "Bo did
        # not" is silence, not an explicit decline.

        {:ok, context}
      end

      given_ "49 quiet turns pass — one short of the strike", context do
        for _ <- 1..49, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      when_ "turn 50 processes", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "Wes's and Ada's commitments reveal simultaneously and both declare independence in the same tick",
            context do
        {:ok, wes_live, _html} = live(context.wes.conn, "/play/#{context.world.id}")
        {:ok, ada_live, _html} = live(context.ada.conn, "/play/#{context.world.id}")

        refute has_element?(wes_live, "[data-test='vassal-status']", "Sworn to #{context.user.email}"),
               "Wes's committed strike should have severed his oath to Mira by turn 50"

        refute has_element?(ada_live, "[data-test='vassal-status']", "Sworn to #{context.user.email}"),
               "Ada's committed strike should have severed her oath to Mira by turn 50"

        assert has_element?(wes_live, "[data-test='rebellion-status']"),
               "Wes should show a declared-independence/rebellion status after the strike"

        assert has_element?(ada_live, "[data-test='rebellion-status']"),
               "Ada should show a declared-independence/rebellion status after the strike"

        {:ok, context}
      end

      then_ "Bo, who never committed, remains a sworn vassal — the strike only sweeps in those who actually committed",
            context do
        {:ok, bo_live, _html} = live(context.bo.conn, "/play/#{context.world.id}")

        assert has_element?(bo_live, "[data-test='vassal-status']", "Sworn to #{context.user.email}"),
               "Bo never committed, so turn 50 should leave his oath to Mira untouched"

        refute has_element?(bo_live, "[data-test='rebellion-status']"),
               "Bo never committed, so he should show no rebellion status at all"

        {:ok, context}
      end
    end
  end
end
