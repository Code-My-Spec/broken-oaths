defmodule BrokenOathsSpex.Story909.Criterion7681Spex do
  @moduledoc """
  Story 909 — Gold Bank and Upgrades
  Criterion 7681 — "once full, accrual STOPS (no gold is lost, but
  idle time is wasted until collected)"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Gold Bank
  (909)"). The overflow contrast to `criterion_7680`'s own plain
  accrual case.

  ## Reconciled against story 912's REAL gold-income mechanic
  (QA issue 589386f2)

  This spec used to declare an absurdly large flat income
  (1,000,000/turn) to guarantee overflow in a single boundary
  (`Fixtures.set_player_gold_income/3`) — `apply_bank/1` no longer
  reads that seam at all now that story 912 shipped a real per-turn
  city gold income mechanic. A REAL city can never earn anywhere near
  that much in one turn, so this instead grows the city to size 4
  first (`base_gold(4) = 3`, a decent real per-turn income) and then
  advances MANY real boundaries — comfortably enough, at even a modest
  few gold per turn, to exceed any plausible starting cap
  (`BrokenOaths.Game.Bank.starting_cap/0` is 100) — reading `Fixtures.
  bank_status/2` directly after each one (a fast, sanctioned, non-UI
  read; see that delegate's own doc) until two consecutive readings
  agree, i.e. accrual has genuinely stopped, not merely slowed. The
  final assertions still go through the real UI badges
  (`criterion_7680`'s own "new judgment calls").
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  @max_turns 250

  spex "the bank holds at the cap and wastes the overflow" do
    scenario "a real offline income, given enough boundaries, fills the bank and stops, never overflowing it" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I go offline, and my grown city earns a real gold income every turn", context do
        grow_city_to(context.world, context.user, context.city.id, 4)
        go_offline(context.play_live)
        {:ok, context}
      end

      when_ "many turn boundaries pass while I'm still offline — enough to fill any plausible cap",
            context do
        Enum.reduce_while(1..@max_turns, nil, fn _, previous ->
          Fixtures.advance_turn(context.world)
          current = Fixtures.bank_status(context.world, context.user).gold

          if current == previous, do: {:halt, :ok}, else: {:cont, current}
        end)

        {:ok, context}
      end

      then_ "the bank reads exactly full — its holdings equal its own cap", context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(play_live, "[data-test='bank-gold']")
        assert has_element?(play_live, "[data-test='bank-cap']")

        bank_html = render(play_live)

        assert [_, bank_gold] = Regex.run(~r/data-test="bank-gold"[^>]*>(\d+)/, bank_html)
        assert [_, bank_cap] = Regex.run(~r/data-test="bank-cap"[^>]*>(\d+)/, bank_html)
        assert bank_gold == bank_cap

        {:ok, Map.put(context, :bank_gold_at_cap, bank_gold)}
      end

      then_ "one more quiet offline turn doesn't move the banked figure at all", context do
        Fixtures.advance_turn(context.world)

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        assert has_element?(play_live, "[data-test='bank-gold']", context.bank_gold_at_cap)
        {:ok, context}
      end
    end
  end
end
