defmodule BrokenOathsSpex.Story878.Criterion7465Spex do
  @moduledoc """
  Story 878 — Settler Founds City
  Criterion 7465 — tiles already claimed by an existing city stay with
  that city; a newly founded neighbor never takes them.

  Model note (spec-writing session 2026-07-14): the literal scenario —
  a brand-new city's FOUNDING ring (radius 1, criterion 7464) covering
  a border tile of an existing city exactly 4 hexes away — is
  geometrically unconstructible. By the triangle inequality, a tile
  within 1 hex of both a founding-ring city A and a legally-spaced
  (>= 4 hexes away) city B can never exist (1 + 1 = 2 < 4). It's
  unreachable within this game's own constraints too: every land tile
  in the fixture world has >= 7 land tiles in its own ring-2, so the
  Stone Age's 3-growth cap (size 1 -> 4) can never push a city's
  territory as far as ring-3 — the minimum reach a contested border
  tile would need.

  The rule's actual intent — "first-come keeps it" — is still
  meaningfully exercised at the point where two neighboring cities'
  GROWTH candidate pools first overlap, which minimum spacing does NOT
  prevent (two cities 4 hexes apart both reach a shared tile 2 hexes
  from each on their very first growth). So this spec drives that:
  city A grows once, claiming a real, seed-discovered tile 2 hexes
  out; city B founds at the legal 4-hex minimum, positioned (by BFS
  search, not a hardcoded direction — robust to whichever tile A's
  yield-driven growth actually picks) so that same tile is also one of
  ITS OWN growth candidates; then B's own growth is asserted to
  respect A's prior claim.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a neighbor founded at minimum spacing never steals claimed tiles" do
    scenario "a shared growth-candidate tile stays with whichever city claimed it first" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the first player founds a city and grows it once", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [c] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [city] = Fixtures.player_cities(context.world, context.user)
        founding_ring = [city.tile_id | Fixtures.adjacent_tiles(context.world, city.tile_id)]
        [claimed_tile] = city.territory -- founding_ring

        {:ok, context |> Map.put(:city, city) |> Map.put(:claimed_tile, claimed_tile)}
      end

      given_ "the second player joins and is on the board", context do
        {:ok, join_live, _html} = live(context.other_conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :other_play_live, play_live)}
      end

      given_ "the second player founds a city exactly 4 hexes from the first, positioned so the claimed tile is also one of its own growth candidates", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        ring = fn start, depth ->
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

        ring4_from_a = ring.(context.city.tile_id, 4) |> MapSet.new()
        ring2_from_claimed = ring.(context.claimed_tile, 2) |> MapSet.new()

        [target | _] = MapSet.to_list(MapSet.intersection(ring4_from_a, ring2_from_claimed))

        render_hook(context.other_play_live, "queue_move", %{
          "unit_id" => settler.id,
          "to_tile" => target
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [u] =
            for uu <- Fixtures.player_units(context.world, context.other_user),
                uu.id == settler.id,
                do: uu

          if u.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [settler] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == settler.id,
              do: u

        render_hook(context.other_play_live, "found_city", %{"unit_id" => settler.id})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        {:ok, Map.put(context, :other_city, other_city)}
      end

      when_ "the second city grows once, toward the shared tile", context do
        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.other_user),
                cc.id == context.other_city.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "the border tile still belongs to the first city", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        assert context.claimed_tile in city.territory
        {:ok, context}
      end

      then_ "the new city's territory simply excludes it", context do
        [other_city] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        refute context.claimed_tile in other_city.territory
        {:ok, context}
      end
    end
  end
end
