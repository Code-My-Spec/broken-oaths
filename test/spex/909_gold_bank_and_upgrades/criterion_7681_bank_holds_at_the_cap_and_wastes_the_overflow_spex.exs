defmodule BrokenOathsSpex.Story909.Criterion7681Spex do
  @moduledoc """
  Story 909 — Gold Bank and Upgrades
  Criterion 7681 — "once full, accrual STOPS (no gold is lost, but
  idle time is wasted until collected)"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Gold Bank
  (909)"). The overflow contrast to `criterion_7680`'s own plain
  accrual case.

  Exact bank size tiers are an open Three Amigos question this spec
  doesn't presume a number for — instead of asserting a specific cap
  value, this spec drives an income so large (1,000,000/turn) across
  several boundaries that it MUST exceed any plausible starting cap,
  then asserts the bank's own two badges agree with EACH OTHER
  (`bank-gold` == `bank-cap`, i.e. genuinely full, not merely large)
  and that a FURTHER quiet turn doesn't move the banked figure at all
  — accrual has stopped, not just slowed.

  See `criterion_7680`'s own moduledoc for the shared `go_offline/1`
  and gold-income-gap judgment calls this reuses unchanged.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the bank holds at the cap and wastes the overflow" do
    scenario "an enormous offline income fills the bank and stops, never overflowing it" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I go offline with a gold income far beyond any plausible bank cap", context do
        go_offline(context.play_live)
        :ok = Fixtures.set_player_gold_income(context.world, context.user, 1_000_000)
        {:ok, context}
      end

      when_ "several turn boundaries pass while I'm still offline", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)
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
