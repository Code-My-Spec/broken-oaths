defmodule BrokenOathsSpex.Story947.Criterion2713Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2713 — the lord/vassal bond is NOT reciprocal, unlike an
  alliance (criterion 2710): `BrokenOaths.Feudal.Stewardship.
  steward_role/4` only ever resolves `:lord` in the direction "owner is
  a vassal, steward is their lord" — there is no clause anywhere that
  could match a vassal acting on their own lord's behalf (the one
  asymmetry this story's design keeps; see that function's own
  moduledoc paragraph, and story 910's own criterion 7687). Each
  direction is independent: the lord may steward the vassal; the
  vassal may never steward the lord back, regardless of anything the
  lord does.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal's grant to their lord is independent of the lord's grant back",
    fail_on_error_logs: false do
    scenario "the lord may steward the vassal, but the vassal may never steward the lord" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline with real banked gold, and I am also offline", context do
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

        go_offline(lord_play_live)
        {:ok, vassal_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        context
        |> Map.put(:vassal_play_live, vassal_play_live)
        |> Map.put(:banked0, banked0)
        |> Map.put(:treasury0, treasury0)
        |> then(&{:ok, &1})
      end

      when_ "the vassal tries to steward the lord's own bank", context do
        attempt_event(context.vassal_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the vassal's attempt on the lord never moved anything", context do
        assert Fixtures.bank_status(context.world, context.other_user).gold ==
                 context.banked0,
               "the vassal's own bank must be untouched by its own refused attempt"

        {:ok, context}
      end

      then_ "the vassal is told they aren't eligible to steward their own lord", context do
        attempt_event(context.vassal_play_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => "0",
          "item" => "warrior"
        })

        assert has_element?(context.vassal_play_live, "[data-test='steward-error']", "eligible")
        {:ok, context}
      end
    end
  end
end
