defmodule BrokenOathsSpex.Story881.Criterion7479Spex do
  @moduledoc """
  Story 881 — Stone Age Warrior Production
  Criterion 7479 — Warriors ride the existing movement substrate at 1
  hex/turn; Settlers keep their established 2 hexes/turn.

  Distance moved is measured as graph (BFS) distance between
  consecutive positions rather than asserting specific tile ids —
  route-agnostic like criterion 7425.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a warrior walks one hex per turn while a settler walks two" do
    scenario "one boundary recharges both units' movement" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a warrior and a settler queued on long paths", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler1 | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler1.id})
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        far_ring = fn start, depth ->
          {frontier, _seen} =
            Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
              next =
                frontier
                |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
                |> Enum.uniq()
                |> Enum.reject(&MapSet.member?(seen, &1))
                |> Enum.filter(land?)

              {next, MapSet.union(seen, MapSet.new(next))}
            end)

          frontier
        end

        [warrior_target | _] = far_ring.(warrior.tile_id, 6)
        render_hook(play_live, "queue_move", %{"unit_id" => warrior.id, "to_tile" => warrior_target})

        {:ok, join_live2, _html} = live(context.other_conn, ~p"/play")

        join_live2
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live2, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        [settler2 | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        [settler_target | _] = far_ring.(settler2.tile_id, 6)

        render_hook(play_live2, "queue_move", %{
          "unit_id" => settler2.id,
          "to_tile" => settler_target
        })

        [warrior_pos0] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        [settler_pos0] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == settler2.id,
              do: u

        {:ok,
         context
         |> Map.put(:warrior, warrior)
         |> Map.put(:settler, settler2)
         |> Map.put(:warrior_tile0, warrior_pos0.tile_id)
         |> Map.put(:settler_tile0, settler_pos0.tile_id)}
      end

      when_ "a turn boundary recharges movement", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the warrior advances one hex", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.warrior.id, do: u

        assert warrior.tile_id in Fixtures.adjacent_tiles(context.world, context.warrior_tile0)
        {:ok, context}
      end

      then_ "the settler advances two", context do
        [settler] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.settler.id,
              do: u

        one_hex_out =
          Fixtures.adjacent_tiles(context.world, context.settler_tile0)
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()

        assert settler.tile_id in one_hex_out
        refute settler.tile_id == context.settler_tile0
        refute settler.tile_id in Fixtures.adjacent_tiles(context.world, context.settler_tile0)
        {:ok, context}
      end
    end
  end
end
