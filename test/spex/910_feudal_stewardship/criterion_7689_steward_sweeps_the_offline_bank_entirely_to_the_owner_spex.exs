defmodule BrokenOathsSpex.Story910.Criterion7689Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7689 — "a steward sweeps the offline player's Gold Bank —
  ALL to the OWNER's treasury (pure stewardship; the steward gets
  nothing; tribute still skims separately)"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). Where `criterion_7686` only tested WHO may fire
  `"steward_collect_bank"`, this criterion is the mechanics themselves:
  the ENTIRE banked figure lands with the owner, and the steward's own
  treasury doesn't move by so much as one gold — "pure stewardship,"
  not a cut.

  See `criterion_7686`'s own moduledoc for the `subjugate/5` setup and
  the `"steward_collect_bank"` judgment call this reuses unchanged.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the steward sweeps the offline bank entirely to the owner", fail_on_error_logs: false do
    scenario "collecting a vassal's bank moves every gold to them, and none to the stewarding lord" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline with 12 gold banked, and my own treasury sits at its own figure",
             context do
        %{lord_play_live: lord_play_live} =
          subjugate(context.world, context.conn, context.user, context.other_conn, context.other_user)

        {:ok, vassal_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        go_offline(vassal_play_live)

        :ok = Fixtures.set_player_gold_income(context.world, context.other_user, 12)
        Fixtures.advance_turn(context.world)

        vassal_treasury0 = Fixtures.gold(context.world, context.other_user)
        lord_treasury0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:vassal_treasury0, vassal_treasury0)
        |> Map.put(:lord_treasury0, lord_treasury0)
        |> then(&{:ok, &1})
      end

      when_ "I steward my vassal's bank", context do
        attempt_event(context.lord_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      then_ "the vassal's own treasury gained the full 12, and mine, the steward's, gained nothing",
            context do
        assert Fixtures.gold(context.world, context.other_user) == context.vassal_treasury0 + 12
        assert Fixtures.gold(context.world, context.user) == context.lord_treasury0
        {:ok, context}
      end
    end
  end
end
