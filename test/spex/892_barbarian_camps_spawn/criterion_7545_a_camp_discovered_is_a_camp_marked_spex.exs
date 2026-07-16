defmodule BrokenOathsSpex.Story892.Criterion7545Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7545 — a barbarian camp that was unexplored becomes a
  distinct marker on the map the moment a player's unit brings its
  tile into sight. Truth surface is the "game:camps" push (mirroring
  "game:cities"/"game:units" — board doctrine: canvas paint is never
  asserted), inferred not-yet-implemented shape `%{id:, tile_id:,
  hp:, warriors: [...]}` (see the Fixtures moduledoc for
  `list_camps/1`).

  The far camp's tile is located via `Fixtures.list_camps/1` (a
  sanctioned ground-truth read, same status as `region_partition` —
  it has no UI surface until scouted) purely to plan the `given_`/
  `when_` (where to walk the lord). The outcome itself — the camp
  appearing on the board — is asserted only through the push event
  the real "queue a move into the fog, walk there across turns"
  surface produces, the same technique criterion 7441 (story 875)
  established for orders into unexplored terrain.

  Every turn advanced while marching re-pushes the whole board, so
  "game:camps" is drained turn-by-turn (matching the latest snapshot,
  not a stale one from turn 1) rather than asserted once after the
  loop — the same staleness pitfall criterion 7442 documents for
  "game:path".
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a camp discovered is a camp marked" do
    scenario "marching the lord within sight of a wilderness camp reveals its marker" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, out of sight of a wilderness camp",
             context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: initial_camps})

        visible_ids = MapSet.new(initial_camps, & &1.tile_id)

        [target_camp | _] =
          context.world
          |> Fixtures.list_camps()
          |> Enum.reject(&MapSet.member?(visible_ids, &1.tile_id))

        land_neighbor =
          context.world
          |> Fixtures.adjacent_tiles(target_camp.tile_id)
          |> Enum.find(&(Fixtures.tile_class(context.world, &1) == :land))

        [scout | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:target_camp, target_camp)
         |> Map.put(:land_neighbor, land_neighbor)
         |> Map.put(:scout, scout)}
      end

      when_ "the lord marches to the camp's doorstep", context do
        {x, y, z} = Fixtures.tile_center(context.world, context.land_neighbor)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.scout.id),
          "to_point" => [x, y, z]
        })

        assert_push_event(context.play_live, "game:camps", %{camps: camps_before})

        scout_now = fn ->
          [u] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == context.scout.id,
                do: u

          u
        end

        {_final_unit, camps_after} =
          Enum.reduce_while(1..60, {scout_now.(), camps_before}, fn _turn, {unit, camps} ->
            if unit.order == nil do
              {:halt, {unit, camps}}
            else
              Fixtures.advance_turn(context.world)
              assert_push_event(context.play_live, "game:camps", %{camps: new_camps}, 500)
              {:cont, {scout_now.(), new_camps}}
            end
          end)

        {:ok,
         context
         |> Map.put(:camps_before_arrival, camps_before)
         |> Map.put(:camps_after_arrival, camps_after)}
      end

      then_ "before the trip the camp was absent, and now it is marked on the map", context do
        refute Enum.any?(context.camps_before_arrival, &(&1.tile_id == context.target_camp.tile_id))

        marker = Enum.find(context.camps_after_arrival, &(&1.tile_id == context.target_camp.tile_id))

        assert marker != nil
        assert marker.id == context.target_camp.id
        assert marker.hp == context.target_camp.hp
        {:ok, context}
      end
    end
  end
end
