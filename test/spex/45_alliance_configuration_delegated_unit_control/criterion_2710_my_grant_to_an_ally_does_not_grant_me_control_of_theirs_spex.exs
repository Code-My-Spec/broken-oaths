defmodule BrokenOathsSpex.Story947.Criterion2710Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2710 — an accepted alliance is not a one-way "grant";
  `BrokenOaths.Feudal.Stewardship.steward_role/4`'s own `:ally` clause
  is already symmetric either direction can steward the other. What
  it does NOT do is bypass the offline requirement in either
  direction: I may not steward MY ally's units just because we're
  allied while THEY are still online — the exact same
  `BrokenOaths.Players.Presence.online?/2` gate criterion 2707 proves
  for the other direction applies here too, on the ally's own side.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens


  spex "a grant to an ally does not grant reciprocal control", fail_on_error_logs: false do
    scenario "I cannot steward my ally's units while they are still online" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the players are accepted allies and my ally is online", context do
        %{play_live_a: owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        {:ok, context |> Map.put(:owner_live, owner_live) |> Map.put(:ally_live, ally_live)}
      end

      when_ "I try to steward my ally's production while they're still online", context do
        attempt_event(context.owner_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.other_user.id),
          "city_id" => "0",
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "my attempt is refused — being allied never bypasses the offline requirement", context do
        assert has_element?(context.owner_live, "[data-test='steward-error']", "online")
        {:ok, context}
      end
    end
  end
end
