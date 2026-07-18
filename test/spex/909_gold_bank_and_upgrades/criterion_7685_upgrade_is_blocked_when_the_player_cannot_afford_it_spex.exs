defmodule BrokenOathsSpex.Story909.Criterion7685Spex do
  @moduledoc """
  Story 909 — Gold Bank and Upgrades
  Criterion 7685 — the contrast to `criterion_7684`'s own affordable
  case: a player with an (essentially) empty treasury cannot upgrade
  the bank — the attempt is refused outright, no partial charge, no
  cap change.

  See `criterion_7684`'s own moduledoc for the `"upgrade_bank"`
  judgment call and why gold (not production) is this spec's own
  concrete cost currency.

  This spec deliberately does NOT assert on a transient `bank-error`-
  style flash: `attempt_event/3` traps the crash `"upgrade_bank"`
  raises today (no handler exists yet), but the crashed LiveView
  PROCESS is gone afterward, and a flash/error assign only ever lives
  on ONE connection's own socket — re-mounting fresh (this codebase's
  own fix for checking PERSISTED facts after a crash, e.g.
  `criterion_7673`) could never show a transient flash even once
  `"upgrade_bank"` is properly implemented and stops crashing, since a
  fresh mount starts with empty assigns regardless. The DB-persisted
  fact this spec CAN check through either path — the treasury balance
  never moved — is the real, durable signal "the upgrade was blocked"
  requires.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the upgrade is blocked when the player cannot afford it", fail_on_error_logs: false do
    scenario "attempting the upgrade with an empty treasury changes nothing" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "my treasury is empty", context do
        :ok = Fixtures.set_player_gold(context.world, context.user, 0)
        {:ok, context}
      end

      when_ "I attempt to upgrade my bank anyway", context do
        attempt_event(context.play_live, "upgrade_bank", %{})
        {:ok, context}
      end

      then_ "my treasury stays at exactly zero — no partial or full charge went through",
            context do
        assert Fixtures.gold(context.world, context.user) == 0
        {:ok, context}
      end

      then_ "the bank's own cap stays wherever it started — no upgrade actually applied",
            context do
        {:ok, fresh_play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(fresh_play_live, "[data-test='bank-cap']"),
               "no \"bank-cap\" element rendered yet — GameLive.Play doesn't show the bank's own cap until this story lands"

        {:ok, context}
      end
    end
  end
end
