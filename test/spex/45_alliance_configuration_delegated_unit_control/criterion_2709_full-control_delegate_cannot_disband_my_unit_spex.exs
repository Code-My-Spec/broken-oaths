defmodule BrokenOathsSpex.Story947.Criterion2709Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2709 — no steward relationship, however trusted, may ever
  disband a unit: `WorldServer`'s own `:steward_disband_unit` handler
  always refuses with `:not_constructive`, unconditionally — "no
  disbanding" is enforced structurally, the same absence-of-a-real-path
  discipline `steward_attack`/`steward_cancel_production_item` share
  (see `BrokenOaths.Feudal.Stewardship`'s own moduledoc).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a Full-control delegate cannot disband the owner's unit", fail_on_error_logs: false do
    scenario "an accepted, eligible ally's disband attempt leaves the unit standing" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted, eligible ally while offline", context do
        %{play_live_a: owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(owner_live)

        [my_lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:my_lord, my_lord)
        |> then(&{:ok, &1})
      end

      when_ "the ally tries to disband my Lord", context do
        attempt_event(context.ally_live, "steward_disband_unit", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => to_string(context.my_lord.id)
        })

        {:ok, context}
      end

      then_ "my Lord still stands", context do
        survivors =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.my_lord.id,
              do: u

        assert survivors != [], "the ally's disband attempt succeeded — it must not"
        {:ok, context}
      end
    end
  end
end
