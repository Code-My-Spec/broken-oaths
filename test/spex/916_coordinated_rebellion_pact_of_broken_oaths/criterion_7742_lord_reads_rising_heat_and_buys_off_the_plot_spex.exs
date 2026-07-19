defmodule BrokenOathsSpex.Story916.Criterion7742Spex do
  @moduledoc """
  Story 916 — Coordinated Rebellion (Pact of Broken Oaths)
  Criterion 7742 — "The lord sees conspiracy heat — whisper volume and
  temperature — not its content, and can make pre-emptive concessions
  to cool strain before the strike turn"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2 —
  first-class Rebellion, Pact-in-chat"), reconciled against this
  story's own task brief, which states the mechanism directly: the lord
  "may sense conspiracy 'heat' (rising aggregate `oath_strain` among
  their vassals — a needle, not the messages) and pre-empt with
  concessions."

  See `BrokenOathsSpex.Story916.Criterion7737Spex`'s own moduledoc for
  the full assumed `RebellionPact` surface contract this spec drives.

  ## Judgment call: "heat" as a NEW numeric `data-test="conspiracy-heat"`
  gauge, aggregated across vassals

  The lord already sees each vassal's EXACT `oath_strain` number today
  (`data-test="vassal-oath-strain"`, real and shipped since story 908 —
  see `vassal_row/1` in `lib/broken_oaths_web/live/game_live/play.ex`),
  which arguably contradicts "not its content" if "heat" just meant
  re-reading that same number. This spec resolves the tension by
  treating "heat" as a genuinely NEW, coarser AGGREGATE across every
  vassal (a single needle for the whole realm, not per-relationship
  detail) rather than a duplicate of the existing per-vassal figure —
  and assumes it renders as a plain integer via
  `data-test="conspiracy-heat"`, mirroring every other gauge already in
  this codebase (`player-honor`, `vassal-oath-strain`). A qualitative
  "Hot"/"Warm"/"Cold" reading is an equally legitimate implementer
  choice this spec doesn't preclude, but a numeric reading is what this
  spec's own before/after cooling comparison needs, so it's the
  assumption actually encoded below.

  ## Judgment call: "honor_protection_call" as an invented lord
  concession

  Neither story 914 (Protection Pact) nor any decay engine for
  `oath_strain` exists yet (confirmed the same way
  `BrokenOathsSpex.Story913.Criterion7723Spex`'s own moduledoc already
  documents for its sibling "gift_vassal"/"declare_shared_enemy"
  seams). This spec invents `"honor_protection_call"`
  (`%{"vassal_user_id" => id}`, fired on the LORD's own connection)
  alongside the REAL, already-shipped `"set_tribute_rate"` lever —
  together the narrowest plausible seam for "lowers tribute rates and
  honors an overdue protection call," both driven via `attempt_event/3`
  since neither has a `handle_event/3` clause today (the tribute-rate
  one for THIS particular invented event; `set_tribute_rate` itself is
  real).

  ## Judgment call: "some conspirators may drop out... a negotiation"
  as reversibility, not a hard requirement

  The gherkin's own "may drop out" is explicitly optional, not a MUST —
  asserting a SPECIFIC dropout as a hard requirement would fabricate a
  rule the design never states. This spec instead asserts the
  STRUCTURAL fact that makes a dropout possible at all: a committed
  conspirator can still change their mind (decline) any time before the
  strike, even after the lord's concessions — that reversibility IS
  what "turns the plotting window into a negotiation" rather than a
  foregone conclusion.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  defp read_strain(live_view, vassal_user_id) do
    html = render(live_view)

    case Regex.run(
           ~r/data-test="vassal-row-#{vassal_user_id}"[\s\S]*?data-test="vassal-oath-strain"[^>]*>(\d+)/,
           html
         ) do
      [_, strain_text] -> String.to_integer(strain_text)
      nil -> nil
    end
  end

  defp read_heat(live_view) do
    case Regex.run(~r/data-test="conspiracy-heat"[^>]*>(\d+)/, render(live_view)) do
      [_, heat_text] -> String.to_integer(heat_text)
      nil -> nil
    end
  end

  spex "Lord reads rising heat and buys off the plot", fail_on_error_logs: false do
    scenario "Lord reads rising heat and buys off the plot" do
      given_ "a world with room for five players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 12}))}
      end

      given_(:registered_player)
      given_(:three_vassals_of_one_lord)

      given_ "a fifth player exists as a legal levy target", context do
        target_user = Fixtures.user_fixture()

        target_conn =
          Phoenix.ConnTest.build_conn()
          |> BrokenOathsTest.ConnCase.log_in_user(target_user)

        {:ok, join_live, _html} = live(target_conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, Map.put(context, :levy_target, %{user: target_user, conn: target_conn})}
      end

      given_(:wes_opened_pact_inviting_ada_and_bo)

      given_ "Wes and Ada commit to the strike", context do
        {:ok, wes_live, _html} = live(context.wes.conn, "/play/#{context.world.id}")
        attempt_event(wes_live, "pact_commit", %{})

        {:ok, ada_live, _html} = live(context.ada.conn, "/play/#{context.world.id}")
        attempt_event(ada_live, "pact_commit", %{})

        {:ok, context}
      end

      given_ "whisper volume among Mira's vassals rises — Wes and Ada each refuse several calls to arms, spiking their real Oath Strain — showing Mira a hot unrest needle but not the messages themselves",
             context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        for vassal <- [context.wes, context.ada] do
          {:ok, vassal_live, _html} = live(vassal.conn, "/play/#{context.world.id}")

          for _ <- 1..7 do
            attempt_event(lord_live, "issue_levy", %{
              "vassal_user_id" => to_string(vassal.user.id),
              "target_user_id" => to_string(context.levy_target.user.id),
              "share" => "0.5"
            })

            attempt_event(vassal_live, "refuse_levy", %{"lord_user_id" => to_string(context.user.id)})
          end
        end

        {:ok, lord_live2, _html} = live(context.conn, "/play/#{context.world.id}")

        refute has_element?(lord_live2, "[data-test='pact-chat']"),
               "the lord senses HEAT only — the pact chat's own content must stay invisible to her"

        strain_before =
          for vassal <- [context.wes, context.ada], into: %{} do
            {vassal.user.id, read_strain(lord_live2, vassal.user.id)}
          end

        {:ok,
         context
         |> Map.put(:heat_before, read_heat(lord_live2))
         |> Map.put(:strain_before, strain_before)}
      end

      when_ "Mira lowers tribute rates for Wes and Ada and honors an overdue protection call before turn 50",
            context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        for vassal <- [context.wes, context.ada] do
          attempt_event(lord_live, "set_tribute_rate", %{
            "vassal_user_id" => to_string(vassal.user.id),
            "rate" => "10"
          })

          attempt_event(lord_live, "honor_protection_call", %{
            "vassal_user_id" => to_string(vassal.user.id)
          })
        end

        {:ok, context}
      end

      then_ "the heat gauge and the conspirators' Oath Strain both cool from Mira's concessions",
            context do
        {:ok, lord_live2, _html} = live(context.conn, "/play/#{context.world.id}")

        assert context.heat_before != nil,
               "expected a numeric conspiracy-heat gauge (data-test='conspiracy-heat') on the lord's own view before any concessions"

        heat_after = read_heat(lord_live2)

        assert heat_after != nil and heat_after < context.heat_before,
               "expected the heat gauge to cool below #{inspect(context.heat_before)} after " <>
                 "concessions, got #{inspect(heat_after)}"

        for vassal <- [context.wes, context.ada] do
          before = Map.fetch!(context.strain_before, vassal.user.id)
          after_ = read_strain(lord_live2, vassal.user.id)

          assert after_ != nil and after_ < before,
                 "Mira's concessions should cool #{vassal.user.email}'s Oath Strain below " <>
                   "#{before}, got #{inspect(after_)}"
        end

        {:ok, context}
      end

      then_ "some conspirators may drop out rather than strike — the plotting window stays a negotiation, not a foregone conclusion",
            context do
        {:ok, wes_live, _html} = live(context.wes.conn, "/play/#{context.world.id}")

        assert has_element?(wes_live, "[data-test='pact-decline']"),
               "a committed conspirator should still be able to back out before the strike once " <>
                 "the lord has made concessions — that reversibility is what turns the plotting " <>
                 "window into a negotiation"

        {:ok, context}
      end
    end
  end
end
