defmodule BrokenOathsSpex.Story891.Criterion7539Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7539 — a unit reduced to 0 HP is destroyed and removed
  from the world: it disappears from the board and its owner's unit
  list, and its tile frees up for movement.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — "the barbarian" here is mechanically a second real
  player's warrior, produced and walked into place through the
  ordinary `GameLive.Play` surface (documented stand-in for story 892,
  `Game.Camps`, which doesn't exist yet).

  The lethal setup uses `Fixtures.set_unit_hp/3` (same documented,
  narrow exception as story 881's healing criteria) to guarantee the
  hit is fatal regardless of the random damage roll.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "zero HP means gone" do
    scenario "a destroyed unit leaves the board and frees its tile" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a combat where one unit's HP falls to 0", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [other_settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        render_hook(other_play_live, "found_city", %{"unit_id" => other_settler.id})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(other_play_live, "queue_production", %{
          "city_id" => other_city.id,
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

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(other_play_live, "queue_move", %{
          "unit_id" => barbarian.id,
          "to_tile" => target
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [b] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == barbarian.id,
                do: u

          if b.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        # Weak enough that any real hit is lethal, regardless of the
        # random damage roll.
        Fixtures.set_unit_hp(context.world, barbarian.id, 1)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_tile, barbarian.tile_id)}
      end

      when_ "the combat resolves", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "that unit disappears from the board and from its owner's unit list, and its tile becomes free for movement",
            context do
        surviving_barbarian =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.barbarian.id,
              do: u

        assert surviving_barbarian == []

        # The tile frees up: a turn boundary recharges my warrior's
        # spent-on-attack movement, then it can be ordered onto the
        # vacated tile without an "occupied" refusal.
        Fixtures.advance_turn(context.world)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.warrior.id,
          "to_tile" => context.barbarian_tile
        })

        refute has_element?(context.play_live, "[data-test='order-error']")

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == context.warrior.id,
                do: u

          if w.tile_id == context.barbarian_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.tile_id == context.barbarian_tile
        {:ok, context}
      end
    end
  end
end
