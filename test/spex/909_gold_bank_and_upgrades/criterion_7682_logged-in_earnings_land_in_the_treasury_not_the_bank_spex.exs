defmodule BrokenOathsSpex.Story909.Criterion7682Spex do
  @moduledoc """
  Story 909 — Gold Bank and Upgrades
  Criterion 7682 — "While the player is LOGGED IN, gold flows to their
  usable treasury directly; while OFFLINE it accrues into the capped
  bank" (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Gold
  Bank (909)"). This is `criterion_7680`'s own mirror image: the SAME
  real income, but with the player's own `GameLive.Play` connection
  kept alive (never disconnected) across the boundary.

  ## Reconciled against story 912's REAL gold-income mechanic
  (QA issue 589386f2)

  See `criterion_7680`'s own moduledoc for the full reconciliation
  rationale (`SharedGivens.real_gold_income/2` in place of the
  test-only `set_player_gold_income/3` seam, which `apply_bank/1` no
  longer reads at all).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "logged-in earnings land in the treasury, not the bank" do
    scenario "staying connected across a boundary credits the treasury directly" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I stay logged in, earning my city's own real gold income", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        income = real_gold_income(context.world, context.user)

        {:ok, context |> Map.put(:treasury0, treasury0) |> Map.put(:income, income)}
      end

      when_ "a turn boundary passes while I'm still connected", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "my treasury grew by my real income, and the bank stayed empty", context do
        assert Fixtures.gold(context.world, context.user) == context.treasury0 + context.income
        assert has_element?(context.play_live, "[data-test='bank-gold']", "0")
        {:ok, context}
      end
    end
  end
end
