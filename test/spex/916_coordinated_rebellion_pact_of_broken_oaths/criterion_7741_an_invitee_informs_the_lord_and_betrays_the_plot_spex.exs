defmodule BrokenOathsSpex.Story916.Criterion7741Spex do
  @moduledoc """
  Story 916 — Coordinated Rebellion (Pact of Broken Oaths)
  Criterion 7741 — "Any member of the pact chat can secretly inform the
  lord of the plot for a personal reward. Informing changes no odds
  (there are none) — it warns the lord, who can then pre-empt: brace
  defenses, reposition the Lord unit, or buy off conspirators before
  the strike turn. The informer's identity stays hidden from the other
  chat members"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2 —
  first-class Rebellion, Pact-in-chat").

  See `BrokenOathsSpex.Story916.Criterion7737Spex`'s own moduledoc for
  the full assumed `RebellionPact` surface contract this spec drives —
  in particular the invented `"pact_inform"` event and the
  `"pact-informed-banner"`/`"informer-reward"`/`"brace-defenses"`/
  `"reposition-lord"`/`"buy-off-conspirators"` selectors.

  ## Judgment call: "identity stays hidden" as absence of a naming
  selector

  There's no sanctioned way for a `then_` to read WHO the lord's own
  view privately knows is the informer (that's exactly the fact meant
  to stay hidden) — only whether the OTHER conspirators' own views ever
  reveal it. This spec refutes a generic `"pact-informer"` selector on
  Wes's and Ada's own views (the two conspirators who are NOT the
  informer) rather than searching their rendered HTML for Bo's email,
  since Bo's email legitimately appears there anyway as an ordinary
  roster entry — only a label naming him AS THE INFORMER would be the
  actual leak this criterion forbids.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an invitee informs the lord and betrays the plot", fail_on_error_logs: false do
    scenario "An invitee informs the lord and betrays the plot" do
      given_ "a world with room for four players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 10}))}
      end

      given_(:registered_player)
      given_(:three_vassals_of_one_lord)
      given_(:wes_opened_pact_inviting_ada_and_bo)

      given_ "Bo was invited to the pact — the precondition above already covers this", context do
        {:ok, context}
      end

      when_ "Bo informs", context do
        {:ok, bo_live, _html} = live(context.bo.conn, "/play/#{context.world.id}")
        attempt_event(bo_live, "pact_inform", %{})

        {:ok, context}
      end

      then_ "Mira learns of the plot (the strike turn and/or the roster) and can now pre-empt",
            context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(lord_live, "[data-test='pact-informed-banner']"),
               "Mira should be warned that a plot against her has been informed on"

        html = render(lord_live)

        assert html =~ "50",
               "the informed-on warning should surface the strike turn (50) named in the pact"

        assert has_element?(lord_live, "[data-test='brace-defenses']"),
               "Mira should be able to brace her defenses once warned"

        assert has_element?(lord_live, "[data-test='reposition-lord']"),
               "Mira should be able to reposition her Lord unit once warned"

        assert has_element?(lord_live, "[data-test='buy-off-conspirators']"),
               "Mira should be able to buy off conspirators with concessions once warned"

        {:ok, context}
      end

      then_ "Bo receives a personal reward such as tribute forgiveness or granted land", context do
        {:ok, bo_live2, _html} = live(context.bo.conn, "/play/#{context.world.id}")

        assert has_element?(bo_live2, "[data-test='informer-reward']"),
               "Bo should see confirmation of his own reward for informing"

        {:ok, context}
      end

      then_ "Bo's identity as the informer stays hidden from the other conspirators", context do
        {:ok, wes_live, _html} = live(context.wes.conn, "/play/#{context.world.id}")
        {:ok, ada_live, _html} = live(context.ada.conn, "/play/#{context.world.id}")

        refute has_element?(wes_live, "[data-test='pact-informer']"),
               "Wes must never see any element revealing who the informer is"

        refute has_element?(ada_live, "[data-test='pact-informer']"),
               "Ada must never see any element revealing who the informer is"

        # Anchor — Bo still renders as an ORDINARY roster member on
        # Wes's own view (the pact chat itself, not "who informed" —
        # writing_a_spex.md's own "don't write vacuous refutes" rule),
        # proving the refutes above aren't passing against a blank page.
        assert has_element?(wes_live, "[data-test='pact-member-status-#{context.bo.user.id}']")

        {:ok, context}
      end
    end
  end
end
