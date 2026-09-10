defmodule BrokenOathsSpex.Story947.Criterion2699Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2699 — a player with no accepted alliance is `:none`
  (`BrokenOaths.Feudal.Stewardship.steward_role/4`) — never eligible
  to steward, regardless of anything the owner does.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens


  spex "granting control to a non-ally is rejected", fail_on_error_logs: false do
    scenario "an unrelated player's steward attempt is refused" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the second player has no accepted alliance with me and I am offline", context do
        {:ok, owner_join, _html} = live(context.conn, "/play")

        owner_join
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, owner_live, _html} = live(context.conn, "/play/#{context.world.id}")
        go_offline(owner_live)

        {:ok, other_join, _html} = live(context.other_conn, "/play")

        other_join
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        {:ok, Map.put(context, :other_live, other_live)}
      end

      when_ "the non-ally tries to steward my production", context do
        attempt_event(context.other_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => "0",
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the non-ally is told they aren't eligible", context do
        assert has_element?(context.other_live, "[data-test='steward-error']", "eligible")
        {:ok, context}
      end
    end
  end
end
