defmodule BrokenOathsSpex.Story910.Criterion7687Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7687 — "Feudal stewardship keeps the asymmetry that lords
  are NEVER stewarded by their vassals (protection flows down)"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). `criterion_7686`'s own contrast: this time the
  LORD is the one who's offline, and the vassal attempts to steward
  THEM — refused outright, no matter how much gold is sitting in the
  lord's own bank.

  See `criterion_7686`'s own moduledoc for the `subjugate/5`
  household-setup helper, the `"steward_collect_bank"` judgment call,
  and the story 912 reconciliation (a real per-turn city gold income
  banks the lord some real gold — the exact figure doesn't matter here,
  since this criterion only asserts nothing moved). `subjugate/5`
  itself never founds a city for the LORD (only the vassal's captured
  one, which stays owned — `player_id` — by the vassal even while
  occupied, per `BrokenOaths.Game.City`'s own doc), so this founds one
  explicitly with the lord's own starting settler — otherwise the lord
  would own zero cities and earn zero real income, leaving nothing for
  this criterion's own "with real banked gold" premise to bank.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal cannot steward their own lord", fail_on_error_logs: false do
    scenario "a vassal's attempt to steward their offline lord's bank changes nothing" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my lord is offline with real banked gold, and I am their vassal", context do
        %{lord_play_live: lord_play_live, vassal_play_live: vassal_play_live} =
          subjugate(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        [lord_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(lord_play_live, "found_city", %{"unit_id" => to_string(lord_settler.id)})

        go_offline(lord_play_live)

        Fixtures.advance_turn(context.world)
        assert Fixtures.bank_status(context.world, context.user).gold > 0

        treasury0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:vassal_play_live, vassal_play_live)
        |> Map.put(:treasury0, treasury0)
        |> then(&{:ok, &1})
      end

      when_ "I, the vassal, attempt to steward my own lord's bank", context do
        attempt_event(context.vassal_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the lord's treasury is untouched — the vassal's attempt was refused", context do
        assert Fixtures.gold(context.world, context.user) == context.treasury0
        {:ok, context}
      end
    end
  end
end
