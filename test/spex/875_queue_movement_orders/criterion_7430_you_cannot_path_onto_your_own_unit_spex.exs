defmodule BrokenOathsSpex.Story875.Criterion7430Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7430 — occupied destinations are invalid at queue time.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "you cannot path onto your own unit" do
    scenario "targeting your own unit's tile is rejected" do
      given_ :a_world
      given_ :registered_player

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end
      when_ "the player targets their settler onto the lord's tile", context do
        units = Fixtures.player_units(context.world, context.user)
        [settler | _] = for u <- units, u.type == :settler, do: u
        [lord | _] = for u <- units, u.type == :lord, do: u

        render_hook(context.play_live, "queue_move", %{"unit_id" => settler.id, "to_tile" => lord.tile_id})
        {:ok, context |> Map.put(:settler, settler) |> Map.put(:lord, lord)}
      end

      then_ "the order is rejected and nothing moves at the boundary", context do
        assert has_element?(context.play_live, "[data-test='order-error']")

        Fixtures.advance_turn(context.world)
        units = Fixtures.player_units(context.world, context.user)
        [settler] = for u <- units, u.id == context.settler.id, do: u
        assert settler.tile_id == context.settler.tile_id
        {:ok, context}
      end
    end
  end
end
