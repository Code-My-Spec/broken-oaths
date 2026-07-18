defmodule BrokenOathsSpex.Story902.Criterion7628Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7628 — Mining speeds up worker mines: once Mining is
  researched, a worker completes a Mine in 3 turns instead of the base
  5 (`BrokenOaths.Game.Research.mine_duration/1` — Mining's own
  moduledoc names `BrokenOaths.Game.Improvement.duration/1` as the
  hardcoded-5 counterpart this unlock must override). This spec drives
  the improvement all the way to completion and checks the tile's
  finished state after exactly 3 turns — not by reading
  `mine_duration/1` directly, but by the real, observable effect a
  player sees: the dig finishing early.

  Uses the same bespoke seed-33 world story 882's mine specs use (the
  default fixture seed has no hills tile — verified by scanning every
  tile of its 642-tile globe).

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Mining speeds up worker mines" do
    scenario "a mine finishes in 3 turns once Mining is researched" do
      given_(:registered_player)

      given_ "a worker digging a mine on hills, with Mining already researched", context do
        world = Fixtures.world_fixture(%{seed: 33})
        land? = fn t -> Fixtures.tile_class(world, t) == :land end

        hills_tile =
          Enum.find(0..(Fixtures.tile_count(world) - 1), fn t ->
            land?.(t) and Fixtures.tile_terrain(world, t).relief == :hills
          end)

        founding_tile = Fixtures.adjacent_tiles(world, hills_tile) |> Enum.find(land?)

        {:ok, join_live, _html} = live(context.conn, ~p"/play")
        join_live |> element("[data-test='join-world-#{world.id}']") |> render_click()
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(world, context.user), u.type == :settler, do: u

        render_hook(play_live, "queue_move", %{
          "unit_id" => settler.id,
          "to_tile" => founding_tile
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [s] = for u <- Fixtures.player_units(world, context.user), u.id == settler.id, do: u

          if s.tile_id == founding_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})

        render_hook(play_live, "toggle_tech_panel", %{})
        render_hook(play_live, "select_research", %{"tech" => "mining"})

        # Mining costs 75 science at 2/turn for a size-1 city (~38
        # turns); the queued worker (60 production, flat 5/turn base)
        # finishes comfortably within that same wait.
        Enum.reduce_while(1..45, :ok, fn _, :ok ->
          if has_element?(play_live, "[data-test='tech-completed-mining']") do
            {:halt, :ok}
          else
            Fixtures.advance_turn(world)
            {:cont, :ok}
          end
        end)

        assert has_element?(play_live, "[data-test='tech-completed-mining']"),
               "Mining never completed within 45 turns"

        [worker] = for u <- Fixtures.player_units(world, context.user), u.type == :worker, do: u
        render_hook(play_live, "queue_move", %{"unit_id" => worker.id, "to_tile" => hills_tile})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(world, context.user), u.id == worker.id, do: u

          if w.tile_id == hills_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "select_unit", %{"unit_id" => worker.id})
        render_hook(play_live, "start_improvement", %{"unit_id" => worker.id, "kind" => "mine"})

        {:ok,
         context
         |> Map.put(:world_hw, world)
         |> Map.put(:play_live, play_live)
         |> Map.put(:hills_tile, hills_tile)}
      end

      when_ "three turn boundaries pass", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world_hw)
        {:ok, context}
      end

      then_ "the mine is already complete — Mining's 3-turn duration, not the base 5", context do
        assert Fixtures.tile_improvement(context.world_hw, context.hills_tile) == :mine
        {:ok, context}
      end
    end
  end
end
