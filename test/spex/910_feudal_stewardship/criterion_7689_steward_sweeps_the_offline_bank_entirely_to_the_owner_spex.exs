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

  See `criterion_7686`'s own moduledoc for the `subjugate/5` setup, the
  `"steward_collect_bank"` judgment call, and the story 912
  reconciliation this reuses unchanged: `Fixtures.bank_status/2` reads
  the real, banked figure right before it's swept, rather than assuming
  a hand-set number.

  Reuses `subjugate/5`'s own `vassal_play_live` directly (rather than a
  fresh `live/2` remount) before calling `go_offline/1` on it —
  `BrokenOaths.Game.Presence`'s own `:duplicate` Registry keys mean ANY
  live connection for this user counts as "online" (multi-tab support,
  by design), so a stray extra mount left silently connected would
  strand the vassal "online" regardless of which OTHER connection
  `go_offline/1` closes.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the steward sweeps the offline bank entirely to the owner", fail_on_error_logs: false do
    scenario "collecting a vassal's bank moves every gold to them, and none to the stewarding lord" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline with real gold banked, and my own treasury sits at its own figure",
             context do
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

        vassal_treasury0 = Fixtures.gold(context.world, context.other_user)
        lord_treasury0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:banked0, banked0)
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

      then_ "the vassal's own treasury gained the full real banked amount, and mine, the steward's, gained nothing",
            context do
        assert Fixtures.gold(context.world, context.other_user) ==
                 context.vassal_treasury0 + context.banked0

        assert Fixtures.gold(context.world, context.user) == context.lord_treasury0
        {:ok, context}
      end
    end
  end
end
