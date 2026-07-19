defmodule BrokenOathsSpex.Story916.Criterion7738Spex do
  @moduledoc """
  Story 916 — Coordinated Rebellion (Pact of Broken Oaths)
  Criterion 7738 — "Committed strength is hidden from the lord and from
  the other conspirators until the strike — no one sees the full
  roster before the reveal"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2 —
  first-class Rebellion, Pact-in-chat").

  See `BrokenOathsSpex.Story916.Criterion7737Spex`'s own moduledoc for
  the full assumed `RebellionPact` surface contract (events, params,
  `data-test` selectors) this spec drives — this file adds no new
  invented seams of its own.

  ## Judgment call: reading "outstanding, never Committed/Declined"

  The gherkin's own Then is a negative ("Wes cannot see who has
  actually committed") plus a positive ("only that invites are
  outstanding"). This spec encodes both directions: it refutes the
  presence of "Committed"/"Declined" text anywhere near either fellow
  member's own status row, AND asserts each row still reads
  "Outstanding" — so a naive future implementation that simply omits
  the status element entirely (rather than deliberately masking it)
  would still correctly fail this spec's own positive assertion, not
  just vacuously pass the negative one.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the roster stays secret until the strike", fail_on_error_logs: false do
    scenario "The roster stays secret until the strike" do
      given_ "a world with room for four players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 10}))}
      end

      given_(:registered_player)
      given_(:three_vassals_of_one_lord)
      given_(:wes_opened_pact_inviting_ada_and_bo)

      given_ "Ada has committed and Bo has declined before turn 50", context do
        {:ok, ada_live, _html} = live(context.ada.conn, "/play/#{context.world.id}")
        attempt_event(ada_live, "pact_commit", %{})

        {:ok, bo_live, _html} = live(context.bo.conn, "/play/#{context.world.id}")
        attempt_event(bo_live, "pact_decline", %{})

        {:ok, context}
      end

      when_ "Wes checks the pact before the strike", context do
        {:ok, wes_live, _html} = live(context.wes.conn, "/play/#{context.world.id}")
        {:ok, Map.put(context, :wes_live, wes_live)}
      end

      then_ "Wes cannot see who has actually committed, only that invites are outstanding",
            context do
        html = render(context.wes_live)

        refute html =~
                 ~r/data-test="pact-member-status-#{context.ada.user.id}"[^>]*>\s*Committed/,
               "Ada's commitment must stay hidden from Wes before the strike"

        refute html =~
                 ~r/data-test="pact-member-status-#{context.bo.user.id}"[^>]*>\s*Declined/,
               "Bo's decline must stay hidden from Wes before the strike"

        assert has_element?(
                 context.wes_live,
                 "[data-test='pact-member-status-#{context.ada.user.id}']",
                 "Outstanding"
               ),
               "Ada's own row should read 'Outstanding', not her real answer"

        assert has_element?(
                 context.wes_live,
                 "[data-test='pact-member-status-#{context.bo.user.id}']",
                 "Outstanding"
               ),
               "Bo's own row should read 'Outstanding', not his real answer"

        {:ok, context}
      end

      then_ "Lord Mira cannot see the roster or committed strength at all", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        refute has_element?(lord_live, "[data-test='pact-chat']"),
               "the lord must never see the pact chat itself"

        refute has_element?(lord_live, "[data-test='pact-member-status-#{context.ada.user.id}']"),
               "the lord must never see any member's commitment status"

        refute has_element?(lord_live, "[data-test='pact-member-status-#{context.bo.user.id}']"),
               "the lord must never see any member's commitment status"

        # Anchor — the lord's own view still renders real content, so
        # the refutes above aren't vacuously passing against a blank
        # page (`writing_a_spex.md`'s own "don't write vacuous
        # refutes" rule).
        assert has_element?(lord_live, "[data-test='vassals-list']")

        {:ok, context}
      end
    end
  end
end
