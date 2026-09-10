defmodule BrokenOathsSpex.Story947.Criterion2711Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2711 — a lord-vassal bond is one of the three household
  relationships `BrokenOaths.Feudal.Stewardship.steward_role/4`
  resolves as eligible (`:lord`, alongside `:fellow_vassal` and
  `:ally`) — no separate alliance is needed at all once vassalage
  itself exists. Proven the same way criterion 7686 (story 910) proves
  it: the lord sweeps the offline vassal's real banked gold.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a lord-vassal bond qualifies for a delegated-control grant", fail_on_error_logs: false do
    scenario "the lord can steward their own offline vassal" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline with real banked gold", context do
        %{lord_play_live: lord_play_live, vassal_play_live: vassal_play_live} =
          subjugate(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(vassal_play_live)

        Fixtures.advance_turn(context.world)
        banked0 = Fixtures.bank_status(context.world, context.other_user).gold
        assert banked0 > 0
        treasury0 = Fixtures.gold(context.world, context.other_user)

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:banked0, banked0)
        |> Map.put(:treasury0, treasury0)
        |> then(&{:ok, &1})
      end

      when_ "the lord stewards the vassal's bank", context do
        attempt_event(context.lord_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      then_ "the lord-vassal bond was a sufficient grant on its own", context do
        assert Fixtures.gold(context.world, context.other_user) ==
                 context.treasury0 + context.banked0

        {:ok, context}
      end
    end
  end
end
