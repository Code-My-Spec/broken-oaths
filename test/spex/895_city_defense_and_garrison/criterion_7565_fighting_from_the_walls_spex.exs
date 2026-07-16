defmodule BrokenOathsSpex.Story895.Criterion7565Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7565 — a unit garrisoned on a city's own tile (a) fights
  with a +50% boost to its combat strength and (b) can strike an
  adjacent barbarian without leaving the tile.

  Reuses story 891's `Game.Combat` surface verbatim (the `"attack"`
  hook, the Civ VI damage curve, adjacency-only attacks with no
  movement) — the only new ingredient is that the attacker starts the
  fight already garrisoned. A player Warrior has Strength 10 =
  Defense 10 (`.code_my_spec/stories/stone_age.md` §4.2), so a ±50%
  "defense" bonus and a hypothetical "attack" bonus land on the same
  number for this unit type — 15 either way — sidestepping which stat
  name the eventual implementation actually boosts.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — "the barbarian" here is mechanically a second real
  player's warrior (Strength 10 = Defense 10, not yet the real 15/15
  Camps-spawned stat, per that story's own known limitation).

  KNOWN LIMITATION: 30 × e^(0.04 × (15 − 10)) ± 25% ≈ [27.5, 45.8],
  rounded to [27, 46] — the same numeric band criterion 7537 derives
  for an unrelated matchup (strength-15 attacker vs. defense-10
  defender); a coincidence of this story's chosen stat values, not a
  copy-paste error.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fighting from the walls" do
    scenario "a garrisoned warrior strikes an adjacent barbarian without leaving the city" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my warrior stands garrisoned on my city's own tile, adjacent to a barbarian", context do
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

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

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

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "I order my garrisoned warrior to attack the barbarian", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "the damage dealt reflects the garrison's boosted combat strength (roughly 27 to 46)",
            context do
        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.barbarian.id,
              do: u

        dealt = context.barbarian_hp0 - barbarian.hp
        assert dealt >= 27 and dealt <= 46
        {:ok, context}
      end

      then_ "my warrior remains garrisoned on the city tile after striking", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.tile_id == context.city.tile_id
        {:ok, context}
      end
    end
  end
end
