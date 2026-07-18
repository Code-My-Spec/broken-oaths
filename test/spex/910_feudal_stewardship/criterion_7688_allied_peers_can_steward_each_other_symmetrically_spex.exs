defmodule BrokenOathsSpex.Story910.Criterion7688Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7688 — "ALLIANCE stewardship is SYMMETRIC/mutual — allied
  peers can each steward the other"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). Unlike the lord/vassal asymmetry
  (`criterion_7687`), an accepted alliance has no "up"/"down" — EITHER
  party can steward the other while offline.

  Alliance itself is REAL, already-shipped functionality (story 901) —
  see `BrokenOathsSpex.SharedGivens.establish_accepted_alliance/5`'s
  own moduledoc for the genuine propose/accept flow this drives through
  `GameLive.AlliancePanel`'s real `"propose_alliance"`/`"accept_alliance"`
  events. Only STEWARDING an ally is new ground — see
  `BrokenOathsSpex.Story910.Criterion7686Spex`'s own moduledoc for the
  shared `"steward_collect_bank"` judgment call and the gold-income
  gap this reuses unchanged.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "allied peers can steward each other symmetrically", fail_on_error_logs: false do
    scenario "each allied peer can sweep the other's bank while they're offline, in either direction" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "we are accepted allies, and I go offline with banked gold", context do
        %{play_live_a: my_play_live, play_live_b: ally_play_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(my_play_live)

        :ok = Fixtures.set_player_gold_income(context.world, context.user, 5)
        Fixtures.advance_turn(context.world)

        treasury0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:ally_play_live, ally_play_live)
        |> Map.put(:treasury0, treasury0)
        |> then(&{:ok, &1})
      end

      when_ "my ally stewards my offline bank", context do
        attempt_event(context.ally_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "my ally's stewardship swept my banked gold into my own treasury", context do
        assert Fixtures.gold(context.world, context.user) == context.treasury0 + 5
        {:ok, context}
      end

      when_ "my ally then goes offline in turn, banking gold of their own, and I steward THEM back",
            context do
        go_offline(context.ally_play_live)

        {:ok, my_play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        :ok = Fixtures.set_player_gold_income(context.world, context.other_user, 5)
        Fixtures.advance_turn(context.world)

        ally_treasury0 = Fixtures.gold(context.world, context.other_user)

        attempt_event(my_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.other_user.id)
        })

        {:ok, Map.put(context, :ally_treasury0, ally_treasury0)}
      end

      then_ "the stewardship works in the OTHER direction too — mutual, not one-way", context do
        assert Fixtures.gold(context.world, context.other_user) == context.ally_treasury0 + 5
        {:ok, context}
      end
    end
  end
end
