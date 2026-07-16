defmodule BrokenOathsSpex.Story883.Criterion7489Spex do
  @moduledoc """
  Story 883 — Settler Production and Expansion
  Criterion 7489 — a produced settler founds a second city under the
  same terrain and 4-hex spacing rules as the first (story 878), and
  nothing else in the world changes because of it (the first-city
  barbarian trigger doesn't fire again).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the second city is founded like the first, minus the drama" do
    scenario "a produced settler founds a second city 4+ hexes away" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a produced settler marched 4+ hexes from the first city", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [founding_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => founding_settler.id})
        [city1] = Fixtures.player_cities(context.world, context.user)

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city1.id, do: cc
          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "queue_production", %{"city_id" => city1.id, "item" => "settler"})
        for _ <- 1..20, do: Fixtures.advance_turn(context.world)

        [new_settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        ring4 =
          Enum.reduce(1..4, {[city1.tile_id], MapSet.new([city1.tile_id])}, fn _, {frontier, seen} ->
            next =
              frontier
              |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
              |> Enum.uniq()
              |> Enum.reject(&MapSet.member?(seen, &1))
              |> Enum.filter(land?)

            {next, MapSet.union(seen, MapSet.new(next))}
          end)
          |> elem(0)

        [target | _] = ring4

        render_hook(play_live, "queue_move", %{"unit_id" => new_settler.id, "to_tile" => target})

        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          [s] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == new_settler.id, do: u

          if s.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == new_settler.id, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city1, city1)
         |> Map.put(:settler, settler)}
      end

      when_ "it founds a second city", context do
        # By now the settler has spent up to ~20 turns producing plus
        # another ~15 marching 4+ hexes, all the while city1 kept
        # accruing food and growing on its own — a stale "city1 is still
        # size 1" assumption from back when the settler was queued
        # doesn't survive that. `found_city` is itself a synchronous
        # action with no turn tick, though, so city1's state immediately
        # before it is the right anchor: "nothing else changes" means
        # this action changes NOTHING about it, whatever size it has
        # organically reached by now.
        [city1_before] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city1.id, do: cc

        render_hook(context.play_live, "found_city", %{"unit_id" => context.settler.id})
        {:ok, Map.put(context, :city1_before_founding, city1_before)}
      end

      then_ "the founding follows the same terrain and spacing rules as the first", context do
        cities = Fixtures.player_cities(context.world, context.user)
        [city2] = for c <- cities, c.id != context.city1.id, do: c

        assert city2.tile_id == context.settler.tile_id
        assert Fixtures.tile_class(context.world, city2.tile_id) == :land

        expected_ring =
          MapSet.new([city2.tile_id | Fixtures.adjacent_tiles(context.world, city2.tile_id)])

        assert MapSet.new(city2.territory) == expected_ring
        {:ok, Map.put(context, :city2, city2)}
      end

      then_ "nothing else changes in the world because of it", context do
        cities = Fixtures.player_cities(context.world, context.user)
        assert length(cities) == 2

        [city1] = for c <- cities, c.id == context.city1.id, do: c
        # `found_city` doesn't tick the turn clock, so city1 — whatever
        # size/food/territory it had organically grown to by the time
        # the second city was founded — must be byte-for-byte identical
        # immediately after.
        assert city1 == context.city1_before_founding

        {:ok, context}
      end
    end
  end
end
