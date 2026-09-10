defmodule BrokenOathsSpex.Story947.Criterion2705Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2705 — a Defensive-only delegate may strike a raider that has
  entered the offline owner's borders.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a Defensive-only delegate strikes a raider inside the owner's borders" do
    scenario "an accepted ally defends an offline owner's territory from a newly entered raider" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner is offline, has granted Defensive-only control, and a raider is inside their borders", context do
        {:ok, ally_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the ally orders the owner's unit to strike the raider", context do
        render_hook(context.ally_live, "steward_defend", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => "1",
          "target_tile" => "2"
        })

        {:ok, context}
      end

      then_ "the defensive strike is accepted", context do
        assert has_element?(context.ally_live, "[data-test='steward-defense-accepted']")
        {:ok, context}
      end

      then_ "the delegate is limited to protecting the owner's borders", context do
        refute has_element?(context.ally_live, "[data-test='steward-offense-accepted']")
        {:ok, context}
      end
    end
  end
end
