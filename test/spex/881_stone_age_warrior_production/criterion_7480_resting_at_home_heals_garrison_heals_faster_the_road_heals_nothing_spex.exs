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

        # A completed warrior's landing tile is always the city center or
        # one of its land neighbors (`Production.landing_tile/3`), so all
        # three already stand somewhere inside the fresh 7-tile founding
        # ring — no assumption about WHICH neighbor is free survives the
        # Lord unit (spawned adjacent to the city) and the other two
        # warriors also occupying ring tiles. Classify roles from where
        # each unit actually landed instead of commanding it to a
        # pre-picked tile that may already be taken: the one standing on
        # the city center is the garrison, one of the two remaining
        # (already resting on a non-center territory tile) is home as-is,
        # and only the last one is walked out past the ring.
        {[garrison_warrior], [home_warrior, abroad_warrior]} =
          Enum.split_with([w1, w2, w3], &(&1.tile_id == city.tile_id))

        # Outside any territory: walk out past the founding ring.
        ring2 =
          Fixtures.adjacent_tiles(context.world, city.tile_id)
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in city.territory))

        [abroad_tile | _] = ring2

        render_hook(play_live, "queue_move", %{"unit_id" => abroad_warrior.id, "to_tile" => abroad_tile})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [u] =
            for uu <- Fixtures.player_units(context.world, context.user),
                uu.id == abroad_warrior.id,
                do: uu

          if u.tile_id == abroad_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        Fixtures.set_unit_hp(context.world, home_warrior.id, 50)
        Fixtures.set_unit_hp(context.world, garrison_warrior.id, 50)
        Fixtures.set_unit_hp(context.world, abroad_warrior.id, 50)

        {:ok,
         context
         |> Map.put(:home_warrior, home_warrior)
         |> Map.put(:garrison_warrior, garrison_warrior)
         |> Map.put(:abroad_warrior, abroad_warrior)}
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
