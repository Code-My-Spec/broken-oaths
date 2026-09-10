defmodule BrokenOathsSpex.Story947.Criterion2704Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2704 — once control is revoked, the ally's next attempted order
  is refused.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a revoked ally's next order is refused" do
    scenario "an owner revokes a previously granted ally control" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has granted Full control to an accepted ally", context do
        {:ok, owner_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, ally_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        {:ok, context |> Map.put(:owner_live, owner_live) |> Map.put(:ally_live, ally_live)}
      end

      when_ "the owner revokes the grant and the ally tries to issue another order", context do
        render_hook(context.owner_live, "set_delegated_control", %{
          "ally_user_id" => to_string(context.other_user.id),
          "level" => "none"
        })

        render_hook(context.ally_live, "steward_move", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => "1",
          "to_tile" => "2"
        })

        {:ok, context}
      end

      then_ "the ally's next delegated order is refused", context do
        refute has_element?(context.ally_live, "[data-test='steward-order-accepted']")
        {:ok, context}
      end

      then_ "the ally is shown that their control was revoked", context do
        assert has_element?(context.ally_live, "[data-test='steward-error']", "control")
        {:ok, context}
      end
    end
  end
end
