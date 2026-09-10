defmodule BrokenOathsSpex.Story947.Criterion2702Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2702 — a Defensive-only ally may repel an attacker threatening
  the offline owner's city.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a Defensive-only ally repels an attacker on the owner's city" do
    scenario "an offline owner grants an accepted ally Defensive-only control during an attack" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner is offline, has granted Defensive-only control, and their city is under attack", context do
        {:ok, ally_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the ally orders the owner's defending unit to repel the attacker", context do
        render_hook(context.ally_live, "steward_defend", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => "1",
          "target_tile" => "2"
        })

        {:ok, context}
      end

      then_ "the defensive order is accepted to protect the owner's city", context do
        assert has_element?(context.ally_live, "[data-test='steward-defense-accepted']")
        {:ok, context}
      end

      then_ "the ally is not given unrelated offensive control", context do
        refute has_element?(context.ally_live, "[data-test='steward-offense-accepted']")
        {:ok, context}
      end
    end
  end
end
