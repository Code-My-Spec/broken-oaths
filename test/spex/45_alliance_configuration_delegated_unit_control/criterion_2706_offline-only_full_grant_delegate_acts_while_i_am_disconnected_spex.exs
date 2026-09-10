defmodule BrokenOathsSpex.Story947.Criterion2706Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2706 — every real steward eligibility check
  (`BrokenOaths.Feudal.Stewardship.fetch_context/3`) is unconditionally
  gated on the owner being genuinely offline
  (`BrokenOaths.Players.Presence.online?/2`) — there is no separate
  "offline-only" vs "always-on" toggle to configure; ALL stewardship
  is offline-only, by construction. This half proves the accepted
  case: an eligible ally acts while the owner is disconnected.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an offline-only Full grant lets the delegate act while the owner is disconnected",
    fail_on_error_logs: false do
    scenario "an accepted ally sweeps my bank while I'm disconnected" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted ally and real banked gold while disconnected", context do
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

        Fixtures.advance_turn(context.world)
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

      then_ "the delegated action actually moved my gold while I was disconnected", context do
        assert Fixtures.gold(context.world, context.user) ==
                 context.treasury0 + context.banked0

        {:ok, context}
      end
    end
  end
end
