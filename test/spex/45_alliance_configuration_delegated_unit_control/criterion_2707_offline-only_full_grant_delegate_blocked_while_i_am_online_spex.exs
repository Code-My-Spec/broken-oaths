defmodule BrokenOathsSpex.Story947.Criterion2707Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2707 — the same unconditional offline gate criterion 2706
  proves (`BrokenOaths.Feudal.Stewardship.fetch_context/3` +
  `BrokenOaths.Players.Presence.online?/2`) blocks an otherwise-eligible
  ally the instant the owner is back online — `:owner_online`,
  `PlayView.steward_error_message/1`'s own "They're back online —
  stewardship has ended."
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens


  spex "an offline-only Full grant blocks the delegate while the owner is online",
    fail_on_error_logs: false do
    scenario "an otherwise-eligible ally's steward attempt is refused while the owner is online" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner is online with an accepted ally", context do
        %{play_live_a: _owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        {:ok, owner_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, context |> Map.put(:owner_live, owner_live) |> Map.put(:ally_live, ally_live)}
      end

      when_ "the ally tries to steward my production while I'm online", context do
        attempt_event(context.ally_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => "0",
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the delegated order is refused while the owner is online", context do
        assert has_element?(context.ally_live, "[data-test='steward-error']", "online")
        {:ok, context}
      end
    end
  end
end
