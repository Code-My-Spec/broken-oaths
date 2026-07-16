defmodule BrokenOathsSpex.Story879.Criterion7472Spex do
  @moduledoc """
  Story 879 — City Production Queue
  Criterion 7472 — if a completed unit has nowhere to spawn (its city
  tile and every adjacent land tile occupied), it waits at the head of
  the queue until a tile frees up; nothing is lost in the meantime.

  The founding city is relocated to a narrow spot with only 4 land
  neighbors (discovered for the fixture seed, not assumed for every
  seed — the search itself is what makes this route-agnostic): the
  city tile plus those 4 neighbors is only 5 tiles to block, reachable
  with three players' starting units (1 + 2 + 2).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a completely blocked city holds the finished unit without losing it" do
    scenario "every tile around the city is occupied when production completes" do
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "a city whose tile and every adjacent land tile are occupied", context do
        # Bespoke world: this scenario needs THREE concurrent players, but
        # the shared fixture world (seed 424242, frequency 8) has exactly
        # TWO spawnable regions — the third join is geometrically
        # impossible there (issue 7509b3e6; verified by Regions.spawnable
        # scan). Frequency 9 / seed 1 deterministically yields three.
        context = Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))

        {:ok, join_live, _html} = live(context.conn, ~p"/play")
        join_live |> element("[data-test='join-world-#{context.world.id}']") |> render_click()
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        # A narrow tile — one with the fewest land neighbors anywhere in
        # this world — keeps the number of blockers needed to a minimum.
        spot =
          0..(Fixtures.tile_count(context.world) - 1)
          |> Enum.filter(land?)
          |> Enum.min_by(fn t -> length(Enum.filter(Fixtures.adjacent_tiles(context.world, t), land?)) end)

        neighbors = Fixtures.adjacent_tiles(context.world, spot) |> Enum.filter(land?)

        walk = fn play_live, world, user, unit, target ->
          render_hook(play_live, "queue_move", %{"unit_id" => unit.id, "to_tile" => target})

          Enum.reduce_while(1..30, :ok, fn _, :ok ->
            [u] = for uu <- Fixtures.player_units(world, user), uu.id == unit.id, do: uu
            if u.tile_id == target do
              {:halt, :ok}
            else
              Fixtures.advance_turn(world)
              {:cont, :ok}
            end
          end)
        end

        units1 = Fixtures.player_units(context.world, context.user)
        [settler1 | _] = for u <- units1, u.type == :settler, do: u
        [lord1 | _] = for u <- units1, u.type == :lord, do: u

        walk.(play_live, context.world, context.user, settler1, spot)
        [settler1] = for u <- Fixtures.player_units(context.world, context.user), u.id == settler1.id, do: u
        render_hook(play_live, "found_city", %{"unit_id" => settler1.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        walk.(play_live, context.world, context.user, lord1, spot)

        {:ok, other_play_live, _html} = live(context.other_conn, ~p"/play")
        other_play_live |> element("[data-test='join-world-#{context.world.id}']") |> render_click()
        {:ok, other_play_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        {:ok, third_play_live, _html} = live(context.third_conn, ~p"/play")
        third_play_live |> element("[data-test='join-world-#{context.world.id}']") |> render_click()
        {:ok, third_play_live, _html} = live(context.third_conn, ~p"/play/#{context.world.id}")

        # Block EVERY land neighbor with the other two players' units —
        # the narrow spot on this world may have 1..4 land neighbors,
        # and four blocker units are available (two per player).
        assert length(neighbors) <= 4

        units2 = Fixtures.player_units(context.world, context.other_user)
        [settler2 | _] = for u <- units2, u.type == :settler, do: u
        [lord2 | _] = for u <- units2, u.type == :lord, do: u

        units3 = Fixtures.player_units(context.world, context.third_user)
        [settler3 | _] = for u <- units3, u.type == :settler, do: u
        [lord3 | _] = for u <- units3, u.type == :lord, do: u

        blockers = [
          {other_play_live, context.other_user, settler2},
          {other_play_live, context.other_user, lord2},
          {third_play_live, context.third_user, settler3},
          {third_play_live, context.third_user, lord3}
        ]

        Enum.zip(neighbors, blockers)
        |> Enum.each(fn {target, {plive, user, unit}} ->
          walk.(plive, context.world, user, unit, target)
        end)

        n1 = hd(neighbors)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:settler2, settler2)
         |> Map.put(:freed_neighbor, n1)}
      end

      when_ "production completes", context do
        for _ <- 1..8, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the finished unit does not appear anywhere", context do
        refute Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.type == :warrior)
               )

        {:ok, context}
      end

      then_ "it spawns automatically as soon as a tile frees up, with no production lost", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        [current | _] = city.queue
        # No production was lost while the queue waited for room.
        assert current.type == :warrior
        assert current.banked >= 40

        # The second player's settler steps off the blocked neighbor tile
        # it was holding — its OWN other neighbors aren't part of the
        # blockade, so it's free to move, and doing so opens exactly one
        # landing spot for the waiting warrior.
        [settler2] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.settler2.id,
              do: u

        alt =
          Fixtures.adjacent_tiles(context.world, settler2.tile_id)
          |> Enum.find(&(Fixtures.tile_class(context.world, &1) == :land and &1 != city.tile_id))

        render_hook(context.other_play_live, "queue_move", %{
          "unit_id" => settler2.id,
          "to_tile" => alt
        })

        Fixtures.advance_turn(context.world)

        assert Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.type == :warrior)
               )

        {:ok, context}
      end
    end
  end
end
