defmodule BrokenOathsSpex.Story882.Criterion7699Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7699 — playtest update (issue 1caa87e9, worker build
  charges): charges are only ever spent on COMPLETION, never on
  starting or abandoning a build, so cancelling a build in progress
  costs no charge and never expends the worker.

  Needs a hills tile (Mine, 5 turns) — same bespoke seed-33 world
  `Criterion7484Spex` already uses for the same reason (the project's
  default fixture seed generates no hills anywhere on its globe).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an abandoned dig costs no charge" do
    scenario "the player cancels a Mine build before it completes" do
      given_(:registered_player)

      given_ "a worker with 3 build charges that has started but not finished a Mine", context do
        world = Fixtures.world_fixture(%{seed: 33})
        land? = fn t -> Fixtures.tile_class(world, t) == :land end

        hills_tile =
          Enum.find(0..(Fixtures.tile_count(world) - 1), fn t ->
            land?.(t) and Fixtures.tile_terrain(world, t).relief == :hills
          end)

        {:ok, join_live, _html} = live(context.conn, ~p"/play")
        join_live |> element("[data-test='join-world-#{world.id}']") |> render_click()
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{world.id}")

        {:ok, player} = Fixtures.join_world(world, context.user)
        worker = Fixtures.spawn_unit(world, player.id, :worker, hills_tile)
        assert worker.charges == 3

        render_hook(play_live, "select_unit", %{"unit_id" => worker.id})
        render_hook(play_live, "start_improvement", %{"unit_id" => worker.id, "kind" => "mine"})

        # Mine takes 5 turns; two boundaries leaves it well short of done.
        for _ <- 1..2, do: Fixtures.advance_turn(world)
        refute Fixtures.tile_improvement(world, hills_tile) == :mine

        {:ok,
         context
         |> Map.put(:world, world)
         |> Map.put(:play_live, play_live)
         |> Map.put(:worker, worker)
         |> Map.put(:hills_tile, hills_tile)}
      end

      when_ "the player cancels the build before it completes", context do
        render_hook(context.play_live, "cancel_improvement", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "the worker still has 3 build charges and is not expended", context do
        worker =
          Enum.find(
            Fixtures.player_units(context.world, context.user),
            &(&1.id == context.worker.id)
          )

        refute is_nil(worker)
        assert worker.charges == 3

        {:ok, context}
      end
    end
  end
end
