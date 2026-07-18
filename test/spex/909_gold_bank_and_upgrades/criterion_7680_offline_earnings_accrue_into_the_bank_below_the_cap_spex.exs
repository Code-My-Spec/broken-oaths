defmodule BrokenOathsSpex.Story909.Criterion7680Spex do
  @moduledoc """
  Story 909 — Gold Bank and Upgrades
  Criterion 7680 — "Gold earned while the player is OFFLINE accrues
  into the bank up to its cap"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Gold Bank
  (909)"). This criterion is the plain accrual case: a modest income,
  comfortably below whatever the eventual bank cap turns out to be
  (Three Amigos own tiers/curve — this spec picks a small, conservative
  income specifically so it never risks colliding with that open
  question; `criterion_7681` is the OVERFLOW case).

  ## "Offline" — no Presence tracking exists anywhere yet

  A disconnected LiveView socket IS structurally what "the player went
  offline" means for a Phoenix app; this codebase has no Presence/
  online tracking wired up ANYWHERE yet (`BrokenOaths.Game.Bank`, this
  story's own component, doesn't exist either) — see
  `BrokenOathsSpex.SharedGivens.go_offline/1`'s own moduledoc. This
  spec founds a city (which requires being connected), then
  deliberately disconnects that LiveView before the turns that follow,
  the real surface signal a future Presence-based implementation would
  key off.

  ## The gold-income gap, reused from story 908

  No per-turn city gold YIELD mechanic exists yet either — see
  `BrokenOathsSpex.Story908.Criterion7674Spex`'s own moduledoc for the
  full rationale behind `Fixtures.set_player_gold_income/3`, reused
  here unchanged (the SAME gap, not a new one this story introduces).

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
    scenario "a modest income while offline shows up banked, not in the treasury" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I go offline with a modest 5 gold/turn income", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        go_offline(context.play_live)
        :ok = Fixtures.set_player_gold_income(context.world, context.user, 5)

        {:ok, Map.put(context, :treasury0, treasury0)}
      end

      when_ "a turn boundary passes while I'm still offline", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "logging back in shows the 5 gold banked, and my treasury untouched", context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(play_live, "[data-test='bank-gold']", "5")

        assert Fixtures.gold(context.world, context.user) == context.treasury0
        {:ok, context}
      end
    end
  end
end
