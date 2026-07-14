defmodule BrokenOathsSpex.Story875.Criterion7424Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7424 — selecting your unit shows type, hit points, and movement remaining.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "clicking your lord shows the unit panel" do
    scenario "the unit panel shows the lord's details" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "the player selects their Lord", context do
        [lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(context.play_live, "select_unit", %{"unit_id" => lord.id})
        {:ok, Map.put(context, :lord, lord)}
      end

      then_ "the unit panel shows Lord, hit points, and movement remaining", context do
        assert has_element?(context.play_live, "[data-test='unit-panel']")
        assert has_element?(context.play_live, "[data-test='unit-type']", "Lord")
        assert has_element?(context.play_live, "[data-test='unit-hp']")
        assert has_element?(context.play_live, "[data-test='unit-movement']")
        {:ok, context}
      end
    end
  end
end
