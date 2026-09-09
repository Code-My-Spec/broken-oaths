defmodule BrokenOathsSpex.Story947.Criterion2696Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2696 — accepting an alliance alone does not grant unit control.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a newly accepted ally cannot move the owner's units" do
    scenario "an accepted ally attempts to command an owner's unit without a control grant" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the two players have accepted an alliance but no delegated-control grant", context do
        {:ok, owner_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, ally_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        {:ok, context |> Map.put(:owner_live, owner_live) |> Map.put(:ally_live, ally_live)}
      end

      when_ "the ally tries to move one of the owner's units", context do
        render_hook(context.ally_live, "steward_move", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => "1",
          "to_tile" => "2"
        })

        {:ok, context}
      end

      then_ "the owner's unit is not made available for the ally's order", context do
        refute has_element?(context.ally_live, "[data-test='steward-order-accepted']")
        {:ok, context}
      end

      then_ "the ally is told that delegated control has not been granted", context do
        assert has_element?(context.ally_live, "[data-test='steward-error']", "control")
        {:ok, context}
      end
    end
  end
end
