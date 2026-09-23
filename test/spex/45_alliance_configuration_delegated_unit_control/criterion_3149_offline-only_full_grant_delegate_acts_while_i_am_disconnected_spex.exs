defmodule BrokenOathsSpex.Story947.Criterion3149Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 3149 — an offline-only Full grant lets an eligible ally act
  once the owner has genuinely been disconnected well past the
  5-minute grace window (PM decision, 2026-09-09) that gates it — the
  accepted half of the scenario criterion 3159 refuses at the instant
  of disconnect. `advance_turn/1` stands in for the wall-clock timer
  here the same way it does throughout this suite
  (`test/support/fixtures/broken_oaths_spex_fixtures.ex`), so several
  turns pass between disconnect and the steward attempt below.

  An earlier version of this spec asserted the pre-existing, narrower
  `BrokenOaths.Feudal.Stewardship` (910) eligibility gate's
  instant-offline behavior as if it were this story's own scope — the
  claim that "there is no separate offline-only vs always-on toggle;
  ALL stewardship is offline-only by construction" was wrong, and
  story 947's own WARNING (against exactly that mistake, already made
  once in commits 906f84c/50cf632) is why it's gone.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an offline-only Full grant lets the delegate act once the owner has been disconnected past the grace window",
    fail_on_error_logs: false do
    scenario "an accepted ally sweeps my bank well after I disconnect" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted ally and real banked gold, and has been disconnected well past the grace window",
             context do
        %{play_live_a: owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        [my_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(owner_live, "found_city", %{"unit_id" => to_string(my_settler.id)})

        go_offline(owner_live)

        for _ <- 1..5, do: Fixtures.advance_turn(context.world)

        banked0 = Fixtures.bank_status(context.world, context.user).gold
        assert banked0 > 0
        treasury0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:banked0, banked0)
        |> Map.put(:treasury0, treasury0)
        |> then(&{:ok, &1})
      end

      when_ "the ally sweeps my offline bank", context do
        attempt_event(context.ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the delegated action actually moved my gold now that the grace window has elapsed", context do
        assert Fixtures.gold(context.world, context.user) ==
                 context.treasury0 + context.banked0

        {:ok, context}
      end
    end
  end
end
