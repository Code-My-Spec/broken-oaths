defmodule BrokenOathsSpex.Story909.Criterion7680Spex do
  @moduledoc """
  Story 909 — Gold Bank and Upgrades
  Criterion 7680 — "Gold earned while the player is OFFLINE accrues
  into the bank up to its cap"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Gold Bank
  (909)"). This criterion is the plain accrual case: a modest income,
  comfortably below whatever the eventual bank cap turns out to be.

  ## Reconciled against story 912's REAL gold-income mechanic
  (QA issue 589386f2)

  This spec used to declare a flat 5 gold/turn income
  (`Fixtures.set_player_gold_income/3`) — `apply_bank/1` no longer
  reads that seam at all now that story 912 shipped a real per-turn
  city gold income mechanic (`BrokenOaths.Game.Yields.
  city_gold_income/2`, summed by `WorldServer.
  gold_income_by_player/1`). A freshly founded, size-1 city's own real
  income (`SharedGivens.real_gold_income/2`) is `base_gold(1) = 1` at
  minimum — comfortably "modest", the same spirit the original 5-gold
  figure had, and read fresh here rather than assumed.

  ## "Offline" — no Presence tracking exists anywhere yet

  A disconnected LiveView socket IS structurally what "the player went
  offline" means for a Phoenix app — see
  `BrokenOathsSpex.SharedGivens.go_offline/1`'s own moduledoc. This
  spec founds a city (which requires being connected), then
  deliberately disconnects that LiveView before the turn that follows.

  ## New judgment calls this story establishes

  1. `data-test="bank-gold"` — the bank's own current holdings.
  2. `data-test="bank-cap"` — the bank's own current capacity.
     Both new badges on `GameLive.Play`, sibling to the existing
     `data-test="player-gold"` treasury badge.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "offline earnings accrue into the bank below the cap" do
    scenario "a modest real income while offline shows up banked, not in the treasury" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I go offline with my city's own modest, real gold income", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        go_offline(context.play_live)
        income = real_gold_income(context.world, context.user)

        {:ok, context |> Map.put(:treasury0, treasury0) |> Map.put(:income, income)}
      end

      when_ "a turn boundary passes while I'm still offline", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "logging back in shows my real income banked, and my treasury untouched", context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(play_live, "[data-test='bank-gold']", "#{context.income}")

        assert Fixtures.gold(context.world, context.user) == context.treasury0
        {:ok, context}
      end
    end
  end
end
