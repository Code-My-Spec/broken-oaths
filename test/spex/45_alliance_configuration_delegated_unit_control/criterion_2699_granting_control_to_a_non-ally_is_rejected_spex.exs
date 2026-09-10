defmodule BrokenOathsSpex.Story947.Criterion2699Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2699 — control cannot be granted to a player who is not an ally.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "granting control to a non-ally is rejected" do
    scenario "an owner attempts to grant Full control to an unrelated player" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the second player has no accepted alliance with the owner", context do
        {:ok, owner_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :owner_live, owner_live)}
      end

      when_ "the owner tries to grant that non-ally Full delegated control", context do
        render_hook(context.owner_live, "set_delegated_control", %{
          "ally_user_id" => to_string(context.other_user.id),
          "level" => "full"
        })

        {:ok, context}
      end

      then_ "the delegated-control grant is not shown as active", context do
        refute has_element?(context.owner_live, "[data-test='delegated-control-#{context.other_user.id}']", "Full")
        {:ok, context}
      end

      then_ "the owner is told that only an accepted ally may receive control", context do
        assert has_element?(context.owner_live, "[data-test='delegated-control-error']", "ally")
        {:ok, context}
      end
    end
  end
end
