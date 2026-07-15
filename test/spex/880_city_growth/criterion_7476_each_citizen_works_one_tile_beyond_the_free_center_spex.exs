defmodule BrokenOathsSpex.Story880.Criterion7476Spex do
  @moduledoc """
  Story 880 — City Growth
  Criterion 7476 — the city center is always worked free; every
  population point (including the founding one) works one additional
  owned tile, auto-assigned, with a manual override per pop.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "each citizen works one tile beyond the free center" do
    scenario "a size-2 city's worked tiles" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-2 city", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "the player opens the city panel", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})
        {:ok, context}
      end

      then_ "the center tile shows as always worked", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        assert has_element?(
                 context.play_live,
                 "[data-test='city-worked-tile-#{city.tile_id}']"
               )

        refute city.tile_id in city.worked_tiles
        {:ok, Map.put(context, :grown_city, city)}
      end

      then_ "exactly two more territory tiles are marked worked", context do
        assert length(context.grown_city.worked_tiles) == 2

        for t <- context.grown_city.worked_tiles do
          assert t in context.grown_city.territory
          assert has_element?(context.play_live, "[data-test='city-worked-tile-#{t}']")
        end

        {:ok, context}
      end

      then_ "the player can reassign which tiles those are", context do
        city = context.grown_city
        [old_tile | _] = city.worked_tiles

        replacement =
          Enum.find(
            city.territory -- [city.tile_id | city.worked_tiles],
            &(Fixtures.tile_class(context.world, &1) == :land)
          )

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => city.id,
          "from_tile_id" => old_tile,
          "to_tile_id" => replacement
        })

        [updated] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc

        refute old_tile in updated.worked_tiles
        assert replacement in updated.worked_tiles
        {:ok, context}
      end
    end
  end
end
