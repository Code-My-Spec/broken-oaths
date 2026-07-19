defmodule BrokenOathsSpex.Story909.Criterion7683Spex do
  @moduledoc """
  Story 909 — Gold Bank and Upgrades
  Criterion 7683 — "COLLECT = a click that sweeps bank -> treasury (a
  deliberate engagement tap)"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Gold Bank
  (909)"). Builds on `criterion_7680`'s own offline-accrual setup: gold
  is already sitting in the bank; this criterion is the collect action
  itself.

  ## Reconciled against story 912's REAL gold-income mechanic
  (QA issue 589386f2)

  See `criterion_7680`'s own moduledoc for the full reconciliation
  rationale (`SharedGivens.real_gold_income/2` in place of the
  test-only `set_player_gold_income/3` seam). Whatever real income the
  founded city banked over the one offline turn (read via `Fixtures.
  bank_status/2` right before clicking Collect, rather than assumed) is
  exactly what Collect should sweep — this is the mechanism under test,
  not the specific number.

  ## This criterion's own new judgment call

  `"collect_bank"`, no params (a player only ever has one bank, their
  own) — driven through `attempt_event/3` since no `handle_event/3`
  clause exists for it yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "collect sweeps the banked gold into the treasury", fail_on_error_logs: false do
    scenario "clicking collect moves the banked gold into the treasury and empties the bank" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I logged back in with real gold already sitting in my bank", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        go_offline(context.play_live)
        Fixtures.advance_turn(context.world)

        banked = Fixtures.bank_status(context.world, context.user).gold
        assert banked > 0

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        context
        |> Map.put(:play_live, play_live)
        |> Map.put(:treasury0, treasury0)
        |> Map.put(:banked, banked)
        |> then(&{:ok, &1})
      end

      when_ "I click Collect", context do
        attempt_event(context.play_live, "collect_bank", %{})
        {:ok, context}
      end

      then_ "my treasury gained the real banked gold, and the bank now reads empty", context do
        {:ok, fresh_play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert Fixtures.gold(context.world, context.user) == context.treasury0 + context.banked
        assert has_element?(fresh_play_live, "[data-test='bank-gold']", "0")
        {:ok, context}
      end
    end
  end
end
