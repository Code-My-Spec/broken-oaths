defmodule BrokenOathsSpex.Story1001.Criterion3125Spex do
  @moduledoc """
  Story 1001 — Mutual Peace Without Settlements
  Criterion 3125 — Accepted peace ends the war.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "accepted peace ends a war" do
    scenario "the former rivals no longer see that they are at war" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      given_ "the players are at war and a peace offer is pending", context do
        render_hook(context.play_live, "declare_war", %{
          "counterparty_user_id" => to_string(context.other_user.id)
        })

        render_hook(context.play_live, "offer_peace", %{
          "counterparty_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      when_ "the rival accepts the pending peace offer", context do
        {:ok, rival_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        rival_live
        |> element("[data-test='accept-peace']")
        |> render_click()

        {:ok, context}
      end

      then_ "both players see peace instead of an active war", context do
        {:ok, player_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, rival_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        refute has_element?(player_live, "[data-test='at-war-with']")
        refute has_element?(rival_live, "[data-test='at-war-with']")
        refute has_element?(player_live, "[data-test='pending-peace-offer']")

        {:ok, context}
      end
    end
  end
end
