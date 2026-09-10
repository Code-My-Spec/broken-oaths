defmodule BrokenOathsSpex.Story947.Criterion2698Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2698 — an owner "grants" control to an accepted ally
  simply by the alliance itself becoming `:accepted`
  (`BrokenOaths.Feudal.Stewardship.steward_role/4`'s own `:ally`
  clause) — there is no separate manual grant step. Proven here via
  the real, working steward surface: once accepted, the ally may sweep
  my offline bank.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "granting control to an accepted ally succeeds", fail_on_error_logs: false do
    scenario "the owner's accepted ally is a real, working steward" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the players have accepted an alliance and I have real banked gold offline", context do
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

      when_ "the accepted ally stewards my offline bank", context do
        attempt_event(context.ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the accepted ally's stewardship actually moved my gold", context do
        assert Fixtures.gold(context.world, context.user) ==
                 context.treasury0 + context.banked0

        assert Fixtures.bank_status(context.world, context.user).gold == 0
        {:ok, context}
      end
    end
  end
end
