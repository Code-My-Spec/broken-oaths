defmodule BrokenOathsSpex.Story910.Criterion7686Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7686 — "while a player is OFFLINE they can be stewarded by
  (a) their LORD, (b) their FELLOW VASSALS of the same lord, and (c)
  their ALLIES"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). This criterion is the ELIGIBILITY half: BOTH the
  lord AND a fellow vassal of the SAME lord are accepted stewards for a
  third, offline household member — `criterion_7688` covers the third
  relationship (allies) separately, and `criterion_7687` covers the one
  asymmetry this story keeps (a vassal may never steward their own
  lord).

  Builds on story 907's real Vassalage relationship and story 909's
  real Gold Bank. Household setup uses `BrokenOathsSpex.
  SharedGivens.subjugate/5` (this story's own need for SEVERAL vassals
  under one lord, unlike stories 907/908's single-vassal `a_freshly_
  subjugated_vassal/1`).

  ## Reconciled against story 912's REAL gold-income mechanic
  (QA issue 589386f2)

  This spec used to declare a flat 5 gold/turn income
  (`Fixtures.set_player_gold_income/3`) before each boundary —
  `apply_bank/1` no longer reads that seam at all. The target vassal's
  own REAL per-turn income (their freshly captured city's `base_gold(1)
  = 1` at minimum) is read directly via `Fixtures.bank_status/2` right
  before each steward action instead of assumed, so this stays correct
  regardless of exactly what that income turns out to be.

  ## This criterion's own new judgment call: the steward action itself

  `"steward_collect_bank"`, `%{"owner_user_id" => ...}` — the bank
  sweep (`criterion_7689`'s own full subject) stands in here as "SOME
  steward action," since eligibility ("who may act") and mechanics
  ("what collecting actually moves") are separate concerns this story
  splits across criteria. Driven through `attempt_event/3` since no
  `handle_event/3` clause exists for it yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the lord and a fellow vassal can each steward an offline household member",
    fail_on_error_logs: false do
    scenario "both the lord and a sibling vassal can sweep a third, offline vassal's bank" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "a lord holds two vassals, one of them (the target) offline with real banked gold",
             context do
        # The sibling vassal (`context.third_user`) is subjugated FIRST
        # — the FELLOW STEWARD this criterion needs, sworn to the same
        # lord as the target before the target itself is captured.
        %{vassal_play_live: sibling_play_live} =
          subjugate(
            context.world,
            context.conn,
            context.user,
            context.third_conn,
            context.third_user
          )

        %{lord_play_live: lord_play_live, vassal_play_live: target_play_live} =
          subjugate(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(target_play_live)

        Fixtures.advance_turn(context.world)

        banked0 = Fixtures.bank_status(context.world, context.other_user).gold
        assert banked0 > 0

        treasury0 = Fixtures.gold(context.world, context.other_user)

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:sibling_play_live, sibling_play_live)
        |> Map.put(:banked0, banked0)
        |> Map.put(:treasury0, treasury0)
        |> then(&{:ok, &1})
      end

      when_ "the lord stewards the offline vassal's bank", context do
        attempt_event(context.lord_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      then_ "the lord's stewardship swept the banked gold into the owner's treasury", context do
        assert Fixtures.gold(context.world, context.other_user) ==
                 context.treasury0 + context.banked0

        assert Fixtures.bank_status(context.world, context.other_user).gold == 0
        {:ok, context}
      end

      when_ "a second boundary banks more real gold, and this time a FELLOW VASSAL stewards it",
            context do
        Fixtures.advance_turn(context.world)

        banked1 = Fixtures.bank_status(context.world, context.other_user).gold
        assert banked1 > 0

        treasury1 = Fixtures.gold(context.world, context.other_user)

        attempt_event(context.sibling_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.other_user.id)
        })

        {:ok, context |> Map.put(:banked1, banked1) |> Map.put(:treasury1, treasury1)}
      end

      then_ "the fellow vassal's stewardship ALSO swept the gold into the owner's treasury",
            context do
        assert Fixtures.gold(context.world, context.other_user) ==
                 context.treasury1 + context.banked1

        {:ok, context}
      end
    end
  end
end
