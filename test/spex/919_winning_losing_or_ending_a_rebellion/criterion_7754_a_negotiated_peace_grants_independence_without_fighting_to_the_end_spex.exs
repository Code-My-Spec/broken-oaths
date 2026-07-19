defmodule BrokenOathsSpex.Story919.Criterion7754Spex do
  @moduledoc """
  Story 919 — Winning, Losing, or Ending a Rebellion
  Criterion 7754 — "NEGOTIATED PEACE is a mutually-agreed end that BOTH
  sides must accept, and it resolves to one of the two clean outcomes
  only: the rebel is RESTORED as a vassal, or GRANTED full independence.
  Nobody loses cities in a peace — optional gold reparations (winner to
  loser) may sweeten the deal. If the sides cannot agree, the war simply
  continues to a military decision."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2").

  Reuses `"declare_independence"` and `data-test="rebellion-status"`
  from criterion_7751's own moduledoc.

  ## Flagged simplification: "holding some cities... others"

  The Gherkin's own Given describes a multi-city stalemate ("Wes
  holding some of his cities and Mira still holding others"). Every
  other criterion in this feudal batch — including this story's own
  siblings 7751-7753 — builds on `a_freshly_subjugated_vassal/1`, this
  batch's established SINGLE-city vassal fixture (founding and
  besieging a SECOND city has no shortcut anywhere in this batch; it
  would mean growing a fresh settler out of production, story 883,
  purely to stand in for flavor text). This spec uses that same
  single-contested-city setup as the concrete stand-in for "stalemated"
  — the wartime-control design note itself says a single occupied city
  under active rebellion becomes "contested (neither fully controls
  until it flips or is re-secured)," which is the substantive fact this
  criterion is actually about (a binary, no-city-loss peace outcome),
  not the plural-city flavor detail. Flagging this rather than fudging
  a second city into existence through a fixture that would itself be
  the kind of shortcut `boundaries.md` warns against.

  ## New judgment calls

  - **`"offer_peace"`**, fired on the OFFERING side's own `play_live`:
    `%{"counterparty_user_id" => ..., "outcome" => "independence" |
    "restore_vassal", "reparations_gold" => "50"}`. Either side may
    offer (the design says "either side may sue for peace"); this
    spec's own scenario has Mira offer, per the Gherkin's own text.
  - **`"accept_peace"`** / **`"reject_peace"`**, fired on the OFFERED
    side's own `play_live`: `%{"counterparty_user_id" => ...}` —
    symmetric to `offer_peace`, unlike `"answer_levy"`'s
    lord-specific `lord_user_id` param, since a peace offer can
    originate from either side.
  - `data-test="city-status"` is NOT new — story 906's own real city
    badge (`city_panel.ex`), rendered only while `@city.status != :free`
    (absence is that criterion's own established anchor for "free").
    "All of his cities are his again" is asserted against that same
    real, already-shipped element.
  - `Fixtures.gold/2` is a sanctioned, already-used read (its own doc:
    "also rendered as `data-test='player-gold'`... a shortcut for the
    SAME fact") — used here to verify the reparations transfer.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  @reparations 50

  spex "Mira offers Wes full independence for reparations, and Wes accepts" do
    scenario "accepting the peace ends the war, frees Wes, and moves the agreed gold" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes's rebellion has stalemated, with a contested city neither side fully controls",
             context do
        context = a_freshly_subjugated_vassal(context)

        attempt_event(context.other_play_live, "declare_independence", %{})

        {:ok,
         context
         |> Map.put(:mira_gold_before, Fixtures.gold(context.world, context.user))
         |> Map.put(:wes_gold_before, Fixtures.gold(context.world, context.other_user))}
      end

      when_ "Mira offers Wes full independence in exchange for gold reparations, and Wes accepts",
            context do
        attempt_event(context.play_live, "offer_peace", %{
          "counterparty_user_id" => to_string(context.other_user.id),
          "outcome" => "independence",
          "reparations_gold" => to_string(@reparations)
        })

        attempt_event(context.other_play_live, "accept_peace", %{
          "counterparty_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the rebellion ends with status peace, Wes is fully independent, and all of his cities are his again",
            context do
        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        {:ok, fresh_mira_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(fresh_wes_live, "[data-test='rebellion-status']", "peace")

        assert has_element?(fresh_wes_live, "[data-test='player-gold']")
        refute has_element?(fresh_wes_live, "[data-test='vassal-status']")
        refute has_element?(fresh_mira_live, "[data-test='vassal-row-#{context.other_user.id}']")

        render_hook(fresh_wes_live, "select_city", %{"city_id" => to_string(context.other_city.id)})

        # Anchor: the city panel itself renders real content...
        assert has_element?(fresh_wes_live, "[data-test='city-size']")
        # ...and carries no "occupied" status badge — the same absence
        # anchor story 906's own criterion 7664 already relies on for
        # "free."
        refute has_element?(fresh_wes_live, "[data-test='city-status']", "occupied")

        {:ok, context}
      end

      then_ "Wes pays the agreed reparations to Mira", context do
        mira_gold_after = Fixtures.gold(context.world, context.user)
        wes_gold_after = Fixtures.gold(context.world, context.other_user)

        assert mira_gold_after == context.mira_gold_before + @reparations
        assert wes_gold_after == context.wes_gold_before - @reparations

        {:ok, context}
      end
    end
  end

  spex "had Wes refused the terms, the war would simply have continued" do
    scenario "refusing the peace offer leaves the rebellion active" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes's rebellion has stalemated, with a contested city neither side fully controls",
             context do
        context = a_freshly_subjugated_vassal(context)

        attempt_event(context.other_play_live, "declare_independence", %{})

        {:ok, context}
      end

      when_ "Mira offers Wes full independence in exchange for gold reparations, and Wes refuses",
            context do
        attempt_event(context.play_live, "offer_peace", %{
          "counterparty_user_id" => to_string(context.other_user.id),
          "outcome" => "independence",
          "reparations_gold" => to_string(@reparations)
        })

        attempt_event(context.other_play_live, "reject_peace", %{
          "counterparty_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the war simply continues — the rebellion stays active, not ended", context do
        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(fresh_wes_live, "[data-test='player-gold']")
        assert has_element?(fresh_wes_live, "[data-test='rebellion-status']", "active")
        refute has_element?(fresh_wes_live, "[data-test='rebellion-status']", "peace")

        {:ok, context}
      end
    end
  end
end
