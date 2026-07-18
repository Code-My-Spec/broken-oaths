defmodule BrokenOathsSpex.Story909.Criterion7684Spex do
  @moduledoc """
  Story 909 — Gold Bank and Upgrades
  Criterion 7684 — "UPGRADE THE BANK: the player can raise the cap
  (costs gold/production) — bigger bank = more offline earnings
  retained. A real economy decision."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Gold Bank
  (909)"). This spec picks GOLD as the concrete cost currency (the
  design doc's own "gold/production" either-or; a Three Amigos tuning
  choice this spec doesn't presume beyond "some cost exists and is
  actually charged").

  ## This criterion's own new judgment call

  `"upgrade_bank"`, no params (a player only ever has one bank of their
  own to upgrade) — driven through `attempt_event/3` since no
  `handle_event/3` clause exists for it yet. A generous starting
  treasury (10,000, well above ANY plausible upgrade cost) sidesteps
  `criterion_7685`'s own "can't afford it" case entirely — that
  criterion is this one's own contrast.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "upgrading the bank raises the cap", fail_on_error_logs: false do
    scenario "upgrading the bank with plenty of gold on hand raises the cap and pays the cost" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I can easily afford the bank upgrade", context do
        :ok = Fixtures.set_player_gold(context.world, context.user, 10_000)

        cap_before_html = render(context.play_live)

        {:ok,
         Map.put(context, :cap_before, Regex.run(~r/data-test="bank-cap"[^>]*>(\d+)/, cap_before_html))}
      end

      when_ "I upgrade my bank", context do
        gold_before_upgrade = Fixtures.gold(context.world, context.user)
        attempt_event(context.play_live, "upgrade_bank", %{})
        {:ok, Map.put(context, :gold_before_upgrade, gold_before_upgrade)}
      end

      then_ "the bank's own cap is now higher, and gold was actually spent on it", context do
        {:ok, fresh_play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(fresh_play_live, "[data-test='bank-cap']")

        cap_after_html = render(fresh_play_live)
        assert [_, cap_after] = Regex.run(~r/data-test="bank-cap"[^>]*>(\d+)/, cap_after_html)

        assert context.cap_before != nil,
               "no \"bank-cap\" element rendered before the upgrade — nothing to compare against"

        [_, cap_before] = context.cap_before
        assert String.to_integer(cap_after) > String.to_integer(cap_before)

        assert Fixtures.gold(context.world, context.user) < context.gold_before_upgrade
        {:ok, context}
      end
    end
  end
end
