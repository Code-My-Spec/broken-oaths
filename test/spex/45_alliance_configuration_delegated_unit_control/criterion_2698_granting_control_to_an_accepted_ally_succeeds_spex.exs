defmodule BrokenOathsSpex.Story947.Criterion2698Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2698 — an owner can grant delegated control to an accepted ally.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "granting control to an accepted ally succeeds" do
    scenario "the owner grants Full control to an accepted ally" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the players have accepted an alliance", context do
        {:ok, owner_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :owner_live, owner_live)}
      end

      when_ "the owner grants the ally Full delegated control", context do
        render_hook(context.owner_live, "set_delegated_control", %{
          "ally_user_id" => to_string(context.other_user.id),
          "level" => "full"
        })

        {:ok, context}
      end

      then_ "the accepted ally is shown as having Full control", context do
        assert has_element?(context.owner_live, "[data-test='delegated-control-level']", "Full")
        {:ok, context}
      end

      then_ "the owner sees the grant saved for that ally", context do
        assert has_element?(context.owner_live, "[data-test='delegated-control-#{context.other_user.id}']")
        {:ok, context}
      end
    end
  end
end
