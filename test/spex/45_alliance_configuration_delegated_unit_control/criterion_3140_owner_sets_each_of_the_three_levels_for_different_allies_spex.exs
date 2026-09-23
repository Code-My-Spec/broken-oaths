defmodule BrokenOathsSpex.Story947.Criterion3140Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 3140 — a control LEVEL is a real, owner-set thing,
  distinct from the accepted-alliance relationship itself
  (`BrokenOaths.Feudal.Stewardship.set_delegated_control/5` +
  `BrokenOaths.Feudal.ControlGrant`): the SAME owner may grant `:full`
  to one accepted ally and `:none` to another, and the two allies get
  genuinely different access despite being equally "accepted" — the
  level is what decides, not the bond alone.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an owner sets different control levels for different accepted allies",
    fail_on_error_logs: false do
    scenario "a :full-granted ally may steward me; a :none-granted ally, though equally accepted, may not" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "I am accepted allies with two different players", context do
        %{play_live_a: first_owner_live, play_live_b: full_ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        # `establish_accepted_alliance/5` leaves the owner's connection
        # ONLINE when it returns — calling it a second time for the
        # same owner would otherwise leave THIS first connection
        # dangling (Presence's `:duplicate` registry counts any live
        # connection as online), so the owner would never look fully
        # offline no matter how many turns pass.
        go_offline(first_owner_live)

        %{play_live_a: owner_live, play_live_b: none_ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.third_conn,
            context.third_user
          )

        context
        |> Map.put(:owner_live, owner_live)
        |> Map.put(:full_ally_live, full_ally_live)
        |> Map.put(:none_ally_live, none_ally_live)
        |> then(&{:ok, &1})
      end

      given_ "I grant one ally Full, always-on control and the other an explicit None", context do
        [my_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.owner_live, "found_city", %{"unit_id" => to_string(my_settler.id)})

        render_hook(context.owner_live, "set_delegated_control", %{
          "delegate_user_id" => to_string(context.other_user.id),
          "level" => "full",
          "mode" => "always_on"
        })

        render_hook(context.owner_live, "set_delegated_control", %{
          "delegate_user_id" => to_string(context.third_user.id),
          "level" => "none",
          "mode" => "offline_only"
        })

        go_offline(context.owner_live)

        banked0 =
          Enum.reduce_while(1..10, 0, fn _, _ ->
            Fixtures.advance_turn(context.world)
            gold = Fixtures.bank_status(context.world, context.user).gold
            if gold > 0, do: {:halt, gold}, else: {:cont, gold}
          end)

        assert banked0 > 0
        treasury0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:banked0, banked0)
        |> Map.put(:treasury0, treasury0)
        |> then(&{:ok, &1})
      end

      when_ "the None-granted ally tries to steward me, then the Full-granted ally does", context do
        attempt_event(context.none_ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        attempt_event(context.none_ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => "0",
          "item" => "warrior"
        })

        attempt_event(context.full_ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "only the Full-granted ally's stewardship actually moved my gold", context do
        assert Fixtures.gold(context.world, context.user) ==
                 context.treasury0 + context.banked0

        assert Fixtures.bank_status(context.world, context.user).gold == 0
        {:ok, context}
      end

      then_ "the None-granted ally is told they haven't been granted that level of control", context do
        assert has_element?(context.none_ally_live, "[data-test='steward-error']", "level")
        {:ok, context}
      end
    end
  end
end
