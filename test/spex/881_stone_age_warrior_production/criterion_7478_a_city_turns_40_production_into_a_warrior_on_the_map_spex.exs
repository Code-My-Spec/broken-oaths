defmodule BrokenOathsSpex.Story881.Criterion7478Spex do
  @moduledoc """
  Story 881 — Stone Age Warrior Production
  Criterion 7478 — a completed Warrior enters play at 100/100 HP,
  movement 1, and the whole game's HP scale rescales alongside it:
  existing Lords to 150 max HP, Settlers to 50.

  The HP-rescale check needs an UNCONSUMED Lord and Settler to look
  at, but founding a city (the only way to get a Warrior onto the
  board) consumes the founder's settler. A second player who never
  founds anything supplies the untouched pair.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a city turns 40 production into a warrior on the map" do
    scenario "a Warrior completes at a size-1 city with a free tile" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a city that completes Warrior production", context do
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

        {:ok, join_live2, _html} = live(context.other_conn, ~p"/play")

        join_live2
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context |> Map.put(:city, city)}
      end

      when_ "the unit spawns", context do
        for _ <- 1..8, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "a warrior with 100/100 HP and movement 1 stands at the city", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        assert warrior.hp == 100
        assert warrior.max_hp == 100
        assert warrior.max_movement == 1
        assert warrior.tile_id == context.city.tile_id
        {:ok, context}
      end

      then_ "existing lords and settlers show 150 and 50 max HP respectively", context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.other_user), u.type == :lord, do: u

        [settler] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        assert lord.max_hp == 150
        assert settler.max_hp == 50
        {:ok, context}
      end
    end
  end
end
