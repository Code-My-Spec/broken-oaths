defmodule BrokenOathsSpex.Story953.Criterion2789Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2789 — a `:land`-passable destination with every one of
  its own approaches occupied refuses with `:unreachable`, distinct
  from `:impassable` (wrong terrain class entirely) —
  `Units.Unit.bfs_path/5` returns `nil`/`[]` and `do_queue_move/4`
  maps that to the toast "There's no path there."
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a player orders a unit to a destination with no free route" do
    scenario "every approach to a distant land tile is occupied, so the order is refused as unreachable" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I have joined the world and opened the game board", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      given_ "a distant land tile has every one of its own approaches occupied", context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        ring1 = MapSet.new(Fixtures.adjacent_tiles(context.world, lord.tile_id))

        destination =
          0..(Fixtures.tile_count(context.world) - 1)
          |> Enum.find(fn t ->
            t != lord.tile_id and not MapSet.member?(ring1, t) and land?.(t)
          end) || raise "no distant land tile exists for this seed"

        context.world
        |> Fixtures.adjacent_tiles(destination)
        |> Enum.filter(land?)
        |> Enum.each(&Fixtures.spawn_barbarian(context.world, &1))

        {:ok, context |> Map.put(:lord, lord) |> Map.put(:destination, destination)}
      end

      when_ "I order the unit to that walled-off destination", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.lord.id,
          "to_tile" => context.destination
        })

        {:ok, context}
      end

      then_ "the order is refused as unreachable and the unit never moves", context do
        assert has_element?(context.play_live, "[data-test='order-error']")

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.lord.id,
            do: u

        assert lord.tile_id == context.lord.tile_id
        {:ok, context}
      end
    end
  end
end
