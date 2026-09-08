defmodule BrokenOathsSpex.Story947.Criterion2696Spex do
  @moduledoc """
  Story 947 — Alliance Configuration — delegated unit control
  Criterion 2696 — a newly accepted ally cannot move the owner's units.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "an ally has no delegated unit-control grant by default" do
    scenario "a newly accepted ally's attempt to move my unit is refused" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "we are accepted allies and I have not granted unit control", context do
        {:ok, owner_join, _html} = live(context.conn, "/play")

        owner_join
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, ally_join, _html} = live(context.other_conn, "/play")

        ally_join
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, ally_play, _html} = live(context.other_conn, "/play/#{context.world.id}")

        {:ok, Map.put(context, :ally_play, ally_play)}
      end

      when_ "my ally orders one of my units to move", context do
        render_hook(context.ally_play, "delegate_move_unit", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the ally sees that no unit-control permission has been granted", context do
        assert has_element?(context.ally_play, "[data-test='delegate-control-error']", "not authorized")
        {:ok, context}
      end
    end
  end
end
