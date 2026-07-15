defmodule BrokenOathsSpex.Story881.Criterion7480Spex do
  @moduledoc """
  Story 881 — Stone Age Warrior Production
  Criterion 7480 — a damaged, unmoved unit heals 10 HP/turn in its
  owner's territory, 15 HP/turn garrisoned on its city's own tile, and
  nothing outside friendly territory.

  Testing healing needs a starting point of damage, and this epic's
  only damage source (combat) is explicitly future work — see
  `BrokenOathsSpex.Fixtures.set_unit_hp/3` for the narrow test-only
  stand-in this spec relies on.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "resting at home heals; garrison heals faster; the road heals nothing" do
    scenario "three damaged warriors in three different situations" do
      given_(:a_world)
      given_(:registered_player)

      given_ "three damaged warriors: one resting in home territory, one garrisoned in its city, one resting outside any territory", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
        for _ <- 1..24, do: Fixtures.advance_turn(context.world)

        [w1, w2, w3 | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        # A home tile: any owned territory tile that isn't the city center.
        home_tile = Enum.find(city.territory, &(&1 != city.tile_id))

        # Outside any territory: walk out past the founding ring.
        ring2 =
          Fixtures.adjacent_tiles(context.world, city.tile_id)
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in city.territory))

        [abroad_tile | _] = ring2

        walk = fn unit, target ->
          render_hook(play_live, "queue_move", %{"unit_id" => unit.id, "to_tile" => target})

          Enum.reduce_while(1..10, :ok, fn _, :ok ->
            [u] = for uu <- Fixtures.player_units(context.world, context.user), uu.id == unit.id, do: uu

            if u.tile_id == target do
              {:halt, :ok}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)
        end

        walk.(w1, home_tile)
        walk.(w2, city.tile_id)
        walk.(w3, abroad_tile)

        Fixtures.set_unit_hp(context.world, w1.id, 50)
        Fixtures.set_unit_hp(context.world, w2.id, 50)
        Fixtures.set_unit_hp(context.world, w3.id, 50)

        {:ok,
         context
         |> Map.put(:home_warrior, w1)
         |> Map.put(:garrison_warrior, w2)
         |> Map.put(:abroad_warrior, w3)}
      end

      when_ "a turn boundary passes with none of them moving", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the one at home gains 10 HP", context do
        [w] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.home_warrior.id,
              do: u

        assert w.hp == 60
        {:ok, context}
      end

      then_ "the garrisoned one gains 15 HP", context do
        [w] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.garrison_warrior.id,
              do: u

        assert w.hp == 65
        {:ok, context}
      end

      then_ "the one abroad gains nothing", context do
        [w] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.abroad_warrior.id,
              do: u

        assert w.hp == 50
        {:ok, context}
      end
    end
  end
end
