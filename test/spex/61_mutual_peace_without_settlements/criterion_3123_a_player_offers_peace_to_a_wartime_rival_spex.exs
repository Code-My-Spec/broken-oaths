defmodule BrokenOathsSpex.Story1001.Criterion3123Spex do
  @moduledoc """
  Story 1001 — Mutual Peace Without Settlements
  Criterion 3123 — A player offers peace to a wartime rival.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a player offers peace to a wartime rival" do
    scenario "the rival can see the pending peace offer" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      given_ "the two discovered players are at war", context do
        render_hook(context.play_live, "declare_war", %{
          "counterparty_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      when_ "the player offers peace to the wartime rival", context do
        render_hook(context.play_live, "offer_peace", %{
          "counterparty_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      then_ "the rival sees a pending offer of peace from the player", context do
        {:ok, rival_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(rival_live, "[data-test='pending-peace-offer']")
        assert has_element?(rival_live, "[data-test='accept-peace']")

        {:ok, context}
      end
    end
  end
end
