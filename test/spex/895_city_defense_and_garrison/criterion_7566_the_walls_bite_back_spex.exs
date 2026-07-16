defmodule BrokenOathsSpex.Story895.Criterion7566Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7566 — a barbarian that attacks a garrisoned city takes
  counter-attack damage from the garrison, on top of the city itself
  losing HP.

  Judgment calls this spec introduces (both new — nothing in stories
  878-892 attacks a city, only units attack units):

    * The `"attack"` hook (story 891) is extended with a
      `"target_city_id"` param as a sibling to the existing
      `"target_unit_id"` — same hook, same attacker-side `unit_id`,
      just a different kind of target. This is the natural extension
      of the one attack surface this codebase already has, rather than
      a second, parallel hook.
    * "City HP shown in city panel" is explicit story copy (§10.3), so
      HP is read from a new `data-test="city-hp"` element on
      `GameLive.CityPanel`, sibling to `city-defense` (criterion 7562)
      and the existing `city-size`/`city-food`. Later criteria in this
      story (7567, 7568) reuse this same element.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — "the barbarian" is a second real player's warrior.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the walls bite back" do
    scenario "a barbarian attacking a garrisoned city takes damage back" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my city stands garrisoned by one warrior, with a barbarian adjacent", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        {:ok, other_join_live, _html} = live(context.other_conn, ~p"/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        [other_settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        render_hook(other_play_live, "found_city", %{"unit_id" => to_string(other_settler.id)})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(other_play_live, "queue_production", %{
          "city_id" => to_string(other_city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        unless warrior.tile_id == city.tile_id do
          render_hook(play_live, "queue_move", %{
            "unit_id" => to_string(warrior.id),
            "to_tile" => city.tile_id
          })

          Enum.reduce_while(1..10, :ok, fn _, :ok ->
            [w] =
              for u <- Fixtures.player_units(context.world, context.user),
                  u.id == warrior.id,
                  do: u

            if w.tile_id == city.tile_id do
              {:halt, :ok}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)
        end

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id]

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(other_play_live, "queue_move", %{
          "unit_id" => to_string(barbarian.id),
          "to_tile" => barbarian_target
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [b] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == barbarian.id,
                do: u

          if b.tile_id == barbarian_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        render_hook(play_live, "select_city", %{"city_id" => to_string(city.id)})
        hp0 = city_hp(play_live)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:city, city)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_hp0, barbarian.hp)
         |> Map.put(:city_hp0, hp0)}
      end

      when_ "the barbarian attacks my city", context do
        render_hook(context.other_play_live, "attack", %{
          "unit_id" => to_string(context.barbarian.id),
          "target_city_id" => to_string(context.city.id)
        })

        {:ok, context}
      end

      then_ "my city loses HP", context do
        assert city_hp(context.play_live) < context.city_hp0
        {:ok, context}
      end

      then_ "the barbarian takes garrison counter-attack damage", context do
        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.barbarian.id,
              do: u

        assert barbarian.hp < context.barbarian_hp0
        {:ok, context}
      end
    end
  end

  # Re-renders the (already-selected) city panel and extracts the
  # integer shown in `data-test="city-hp"`.
  defp city_hp(play_live) do
    html = render(play_live)
    [_, hp] = Regex.run(~r/data-test="city-hp"[^>]*>(\d+)/, html)
    String.to_integer(hp)
  end
end
