defmodule BrokenOathsSpex.Story947.Criterion2703Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2703 — Defensive-only control cannot move an owner's unit
  beyond the owner's territory.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a Defensive-only delegate cannot move units outside the owner's territory" do
    scenario "an accepted ally with Defensive-only control targets a tile beyond the owner's borders" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the owner is offline and has granted the ally Defensive-only control", context do
        {:ok, ally_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :ally_live, ally_live)}
      end

      when_ "the ally tries to move the owner's unit outside its territory", context do
        render_hook(context.ally_live, "steward_defend", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => "1",
          "target_tile" => "999"
        })

        {:ok, context}
      end

      then_ "the out-of-territory move is refused", context do
        refute has_element?(context.ally_live, "[data-test='steward-defense-accepted']")
        {:ok, context}
      end

      then_ "the ally is told that Defensive-only control cannot move the unit outside its territory", context do
        assert has_element?(context.ally_live, "[data-test='steward-error']", "territory")
        {:ok, context}
      end
    end
  end
end
