defmodule BrokenOathsSpex.Story875.Criterion7429Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7429 — two paths converging on one hex resolve to exactly one occupant, deterministically.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.

  Updated for the v0.2.1 playtest "stacking non-combat units" fix
  (issue 5df5de88): a Lord and a Settler — the only two units a fresh
  spawn provides, which this scenario originally raced against each
  other — are now a DELIBERATELY allowed stack (one combat, one
  non-combat unit; see `BrokenOaths.Game.WorldServer.
  field_stack_room?/2`), so two of them converging on a shared tile
  would now correctly end up sharing it rather than colliding. This
  scenario's own subject — same-CLASS convergence still resolves to
  exactly one occupant — is still real and enforced, so it now spawns
  a second Settler (`Fixtures.spawn_unit/4`) to race the first.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "two same-class units racing for the same hex resolve to one occupant" do
    scenario "converging moves of the same combat class never stack" do
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

        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end

        [second_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(settler.tile_id)
          |> Enum.filter(land?)

        second_settler = Fixtures.spawn_unit(context.world, player.id, :settler, second_tile)

        {:ok,
         context
         |> Map.put(:settler, settler)
         |> Map.put(:second_settler, second_settler)}
      end

      given_ "both settlers target the same shared land tile", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end

        shared =
          context.world
          |> Fixtures.adjacent_tiles(context.settler.tile_id)
          |> Enum.filter(land?)
          |> Enum.filter(&(&1 in Fixtures.adjacent_tiles(context.world, context.second_settler.tile_id)))
          |> List.first()

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.settler.id,
          "to_tile" => shared
        })

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.second_settler.id,
          "to_tile" => shared
        })

        {:ok, Map.put(context, :shared, shared)}
      end

      when_ "the turn resolves", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "exactly one unit holds the hex and the other stayed put", context do
        units = Fixtures.player_units(context.world, context.user)
        [settler] = for u <- units, u.id == context.settler.id, do: u
        [second_settler] = for u <- units, u.id == context.second_settler.id, do: u

        occupants = for u <- [settler, second_settler], u.tile_id == context.shared, do: u
        assert length(occupants) == 1
        refute settler.tile_id == second_settler.tile_id

        original = %{
          context.settler.id => context.settler.tile_id,
          context.second_settler.id => context.second_settler.tile_id
        }

        [held_back] = for u <- [settler, second_settler], u.tile_id != context.shared, do: u
        assert held_back.tile_id == Map.fetch!(original, held_back.id)
        {:ok, context}
      end
    end
  end
end
