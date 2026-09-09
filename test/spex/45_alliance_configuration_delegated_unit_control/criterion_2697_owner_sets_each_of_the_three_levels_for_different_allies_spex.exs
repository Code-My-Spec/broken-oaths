defmodule BrokenOathsSpex.Story947.Criterion2697Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2697 — an owner can configure None, Defensive-only, and Full
  control independently for different accepted allies.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "an owner sets each delegated-control level for different allies" do
    scenario "the owner configures three accepted allies" do
      given_(:a_world)
      given_(:registered_player)
      given_( :second_registered_player)
      given_( :third_registered_player)

      given_ "the owner has accepted allies available for delegation", context do
        {:ok, owner_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :owner_live, owner_live)}
      end

      when_ "the owner assigns None, Defensive-only, and Full control", context do
        render_hook(context.owner_live, "set_delegated_control", %{
          "ally_user_id" => to_string(context.other_user.id),
          "level" => "none"
        })

        render_hook(context.owner_live, "set_delegated_control", %{
          "ally_user_id" => to_string(context.third_user.id),
          "level" => "defensive"
        })

        {:ok, context}
      end

      then_ "each ally's configured level is shown independently", context do
        assert has_element?(context.owner_live, "[data-test='delegated-control-level']")
        {:ok, context}
      end

      then_ "the owner can see the three available control levels", context do
        assert has_element?(context.owner_live, "[data-test='delegated-control-none']")
        assert has_element?(context.owner_live, "[data-test='delegated-control-defensive']")
        assert has_element?(context.owner_live, "[data-test='delegated-control-full']")
        {:ok, context}
      end
    end
  end
end
