defmodule BrokenOathsSpex.Story878.Criterion7462Spex do
  @moduledoc """
  Story 878 — Settler Founds City
  Criterion 7462 — founding within 4 hexes of any existing city — even
  one belonging to another player — is refused with a reason.

  Two players share the world: the first founds a city immediately at
  their spawn; the second player's settler is then walked — via the
  same queue_move/advance_turn substrate story 875 already exercises —
  to a tile exactly 3 hexes from that city (BFS over land, route/seed-
  agnostic like criterion 7425) before attempting to found there.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "founding too close to an existing city is refused with a reason" do
    scenario "3 hexes from an existing city, founding is refused" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the first player founds a city", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, Map.put(context, :city, city)}
      end

      given_ "the second player joins and is on the board", context do
        {:ok, join_live, _html} = live(context.other_conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :other_play_live, play_live)}
      end

      given_ "the second player's settler walks to a tile exactly 3 hexes from the city", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        grow = fn frontier, seen ->
          next =
            frontier
            |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
            |> Enum.uniq()
            |> Enum.reject(&MapSet.member?(seen, &1))
            |> Enum.filter(land?)

          {next, MapSet.union(seen, MapSet.new(next))}
        end

        seen = MapSet.new([context.city.tile_id])
        {l1, seen} = grow.([context.city.tile_id], seen)
        {l2, seen} = grow.(l1, seen)
        {l3, _seen} = grow.(l2, seen)

        [target | _] = l3

        render_hook(context.other_play_live, "queue_move", %{
          "unit_id" => settler.id,
          "to_tile" => target
        })

        # Settlers move 2 hexes/turn (story 875); this world's diameter is
        # comfortably under the turn ceiling below.
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

        {:ok, context |> Map.put(:settler, settler) |> Map.put(:target, target)}
      end

      when_ "the second player attempts the Found City action", context do
        render_hook(context.other_play_live, "found_city", %{"unit_id" => context.settler.id})
        {:ok, context}
      end

      then_ "no city is created", context do
        assert Fixtures.player_cities(context.world, context.other_user) == []
        {:ok, context}
      end

      then_ "the player sees why: too close to an existing city", context do
        assert has_element?(context.other_play_live, "[data-test='city-error']")
        {:ok, context}
      end
    end
  end
end
