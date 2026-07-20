defmodule BrokenOathsSpex.Story875.Criterion7430Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7430 — occupied destinations are invalid at queue time.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.

  Updated for the v0.2.1 playtest "stacking non-combat units" fix
  (issue 5df5de88): a Lord and a Settler — the only two units a fresh
  spawn provides, which this scenario originally paired — are now a
  DELIBERATELY allowed stack (one combat, one non-combat unit; see
  `BrokenOaths.Simulation.WorldServer.field_stack_room?/2`). This scenario's
  own subject is still real and enforced — a player can never stack
  two of their own units of the SAME combat class — so it now spawns a
  second Settler (`Fixtures.spawn_unit/4`) to exercise that.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "you cannot path onto your own unit of the same combat class" do
    scenario "targeting your own same-class unit's tile is rejected" do
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

      given_ "a second settler stands nearby (same combat class as the first)", context do
        {:ok, player} = Fixtures.join_world(context.world, context.user)
        units = Fixtures.player_units(context.world, context.user)
        [settler | _] = for u <- units, u.type == :settler, do: u

        [second_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(settler.tile_id)
          |> Enum.filter(&(Fixtures.tile_class(context.world, &1) == :land))

        second_settler = Fixtures.spawn_unit(context.world, player.id, :settler, second_tile)

        {:ok,
         context
         |> Map.put(:settler, settler)
         |> Map.put(:second_settler, second_settler)}
      end

      when_ "the player targets their first settler onto the second settler's tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.settler.id,
          "to_tile" => context.second_settler.tile_id
        })

        {:ok, context}
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
