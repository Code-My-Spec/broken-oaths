defmodule BrokenOathsSpex.Story947.Criterion2700Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2700 — a steward's real actions never spawn a dedicated
  "delegated order feed" UI — audit lives in `BrokenOaths.Feudal.
  StewardLog`'s own click-through log (criterion 7695), not a live
  feed component, and the board itself stays exactly as it always is.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "no order feed exists for a delegate's orders", fail_on_error_logs: false do
    scenario "an accepted ally stewards an offline owner's bank with no feed appearing" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has an accepted ally and real banked gold while offline", context do
        %{play_live_a: owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        [my_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(owner_live, "found_city", %{"unit_id" => to_string(my_settler.id)})

        go_offline(owner_live)

        Fixtures.advance_turn(context.world)

        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the ally stewards the owner's bank", context do
        attempt_event(context.ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the ally sees no order-feed entry for the action", context do
        refute has_element?(context.ally_live, "[data-test='delegated-order-feed']")
        {:ok, context}
      end

      then_ "the game board remains available after the delegated action", context do
        assert has_element?(context.ally_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
