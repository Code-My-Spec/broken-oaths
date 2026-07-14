defmodule BrokenOathsSpex.Story875.Criterion7429Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7429 — two paths converging on one hex resolve to exactly one occupant, deterministically.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "two units racing for the same hex resolve to one occupant" do
    scenario "converging moves never stack" do
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
      given_ "both units target the same shared land tile", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end
        units = Fixtures.player_units(context.world, context.user)
        [settler | _] = for u <- units, u.type == :settler, do: u
        [lord | _] = for u <- units, u.type == :lord, do: u

        shared =
          context.world
          |> Fixtures.adjacent_tiles(settler.tile_id)
          |> Enum.filter(land?)
          |> Enum.filter(&(&1 in Fixtures.adjacent_tiles(context.world, lord.tile_id)))
          |> List.first()

        render_hook(context.play_live, "queue_move", %{"unit_id" => settler.id, "to_tile" => shared})
        render_hook(context.play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => shared})

        {:ok, context |> Map.put(:settler, settler) |> Map.put(:lord, lord) |> Map.put(:shared, shared)}
      end

      when_ "the turn resolves", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "exactly one unit holds the hex and the other stayed put", context do
        units = Fixtures.player_units(context.world, context.user)
        [settler] = for u <- units, u.id == context.settler.id, do: u
        [lord] = for u <- units, u.id == context.lord.id, do: u

        occupants = for u <- [settler, lord], u.tile_id == context.shared, do: u
        assert length(occupants) == 1
        refute settler.tile_id == lord.tile_id

        original = %{context.settler.id => context.settler.tile_id, context.lord.id => context.lord.tile_id}
        [held_back] = for u <- [settler, lord], u.tile_id != context.shared, do: u
        assert held_back.tile_id == Map.fetch!(original, held_back.id)
        {:ok, context}
      end
    end
  end
end
