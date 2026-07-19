defmodule BrokenOathsSpex.Story919.Criterion7752Spex do
  @moduledoc """
  Story 919 — Winning, Losing, or Ending a Rebellion
  Criterion 7752 — "A rebellion ends in INDEPENDENCE WON when the rebel
  holds all of their risen cities for N consecutive turns with no city
  re-occupied by the lord. The severed oath becomes permanent and the
  rebel is free."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2").

  ## Flagged ambiguity: the "N consecutive turns" threshold

  The design doc's own "Three Amigos" note for this batch lists **"the
  'hold for N turns' threshold"** as an explicitly UNRESOLVED item —
  no concrete N is locked anywhere in the story or its knowledge doc.
  This spec picks **N = 10** purely as a deterministic placeholder (the
  same figure story 896's own already-shipped heir-succession timer
  uses for "turns after an event"), NOT a locked design value. Whoever
  implements story 915/919 is free to pick a different N; if they do,
  this scenario's own turn count needs to move with it.

  ## Reused/new judgment calls

  - `"declare_independence"` and `data-test="rebellion-status"` — see
    criterion_7751's own moduledoc for the full rationale.
  - `data-test="vassal-status"` and `data-test="vassal-row-ID"`
    are NOT new — both are real, already-shipped story 907 elements
    (`GameLive.Play`). "The severed oath becomes permanent and the
    rebel is free" is asserted against THESE real elements: a freed
    rebel's own view stops rendering `vassal-status` at all (the exact
    same absence anchor story 907's own "no vassals-list at all"
    criterion already relies on), and the former lord's own
    `vassal-row` for that rebel disappears from their Vassals list.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  @hold_turns 10

  spex "holding the freed cities wins independence" do
    scenario "ten uncontested turns after declaring independence, Wes wins his freedom" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes's rebellion is active and all of his risen cities are held by Wes",
             context do
        context = a_freshly_subjugated_vassal(context)

        attempt_event(context.other_play_live, "declare_independence", %{})

        {:ok, context}
      end

      when_ "#{@hold_turns} consecutive turns pass with no city re-occupied by Lord Mira",
            context do
        for _ <- 1..@hold_turns, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the rebellion ends with status independence_won", context do
        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(fresh_wes_live, "[data-test='rebellion-status']", "independence_won")

        {:ok, context}
      end

      then_ "the severed oath becomes permanent and Wes is free", context do
        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        {:ok, fresh_mira_live, _html} = live(context.conn, "/play/#{context.world.id}")

        # Anchor: the freed player's own board still renders real
        # content (their treasury badge is unconditional) — proving the
        # refute below isn't just an empty page.
        assert has_element?(fresh_wes_live, "[data-test='player-gold']")
        refute has_element?(fresh_wes_live, "[data-test='vassal-status']")
        refute has_element?(fresh_mira_live, "[data-test='vassal-row-#{context.other_user.id}']")

        # Permanence: several MORE turns pass and the freedom holds —
        # never reverts.
        for _ <- 1..5, do: Fixtures.advance_turn(context.world)

        {:ok, still_free_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        {:ok, still_free_mira_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(still_free_wes_live, "[data-test='rebellion-status']", "independence_won")
        refute has_element?(still_free_wes_live, "[data-test='vassal-status']")
        refute has_element?(
                 still_free_mira_live,
                 "[data-test='vassal-row-#{context.other_user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
