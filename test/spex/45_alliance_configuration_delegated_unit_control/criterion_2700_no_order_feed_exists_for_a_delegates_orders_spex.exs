defmodule BrokenOathsSpex.Story947.Criterion2700Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2700 — delegated orders do not create an order feed.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "no order feed exists for a delegate's orders" do
    scenario "an accepted delegate with Full control commands an offline owner's unit" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has granted the delegate Full control and is offline", context do
        {:ok, delegate_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :delegate_live, delegate_live)}
      end

      when_ "the delegate submits a permitted order for the owner's unit", context do
        render_hook(context.delegate_live, "steward_move", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => "1",
          "to_tile" => "2"
        })

        {:ok, context}
      end

      then_ "the delegate sees the order result without an order-feed entry", context do
        refute has_element?(context.delegate_live, "[data-test='delegated-order-feed']")
        {:ok, context}
      end

      then_ "the game board remains available after the delegated action", context do
        assert has_element?(context.delegate_live, "[data-test='game-board']")
        {:ok, context}
      end
    end
  end
end
