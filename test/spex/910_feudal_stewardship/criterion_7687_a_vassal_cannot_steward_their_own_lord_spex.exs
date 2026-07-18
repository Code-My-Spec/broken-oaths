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
  household-setup helper and the `"steward_collect_bank"` judgment
  call this reuses unchanged.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal cannot steward their own lord", fail_on_error_logs: false do
    scenario "a vassal's attempt to steward their offline lord's bank changes nothing" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my lord is offline with banked gold, and I am their vassal", context do
        %{lord_play_live: lord_play_live, vassal_play_live: vassal_play_live} =
          subjugate(context.world, context.conn, context.user, context.other_conn, context.other_user)

        go_offline(lord_play_live)

        :ok = Fixtures.set_player_gold_income(context.world, context.user, 5)
        Fixtures.advance_turn(context.world)

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
