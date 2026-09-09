defmodule BrokenOathsSpex.Story947.Criterion2701Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2701 — Full control cannot give an ally authority to start a war
  the owner could not start.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a Full-control ally cannot start a war the owner could not start" do
    scenario "an offline owner has granted an accepted ally Full control" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner has granted Full control to the accepted ally while a hostile action is unavailable", context do
        {:ok, ally_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the ally tries to use the owner's unit to start that war", context do
        render_hook(context.ally_live, "steward_attack", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => "1",
          "target_player_id" => "999"
        })

        {:ok, context}
      end

      then_ "the delegated attack is refused", context do
        refute has_element?(context.ally_live, "[data-test='steward-attack-accepted']")
        {:ok, context}
      end

      then_ "the ally is told that Full control does not create new war authority", context do
        assert has_element?(context.ally_live, "[data-test='steward-error']", "war")
        {:ok, context}
      end
    end
  end
end
