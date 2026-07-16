defmodule BrokenOathsSpex.Story891.Criterion7538Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7538 — attacker and defender damage each other
  simultaneously, both computed from pre-combat state, so a dying
  defender still lands its counter-blow: my warrior still takes the
  barbarian's counter-damage even though the barbarian is destroyed by
  the same exchange.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — "the barbarian" here is mechanically a second real
  player's warrior, produced and walked into place through the
  ordinary `GameLive.Play` surface (documented stand-in for story 892,
  `Game.Camps`, which doesn't exist yet).

  "Weak enough that my next hit destroys it" is engineered with
  `Fixtures.set_unit_hp/3` — the same documented, narrow exception to
  the read-only bridge that story 881's healing criteria already rely
  on (there is still no in-game way to damage a unit down to a
  specific low HP before combat exists to do it for real).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the killing blow is not free" do
    scenario "a lethal hit still costs the attacker HP" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a barbarian warrior weak enough that my next hit destroys it", context do
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

        # Weak enough that any real hit destroys it — well below the
        # combat curve's smallest possible roll (~18, per criterion
        # 7537) — while still alive to swing back this same exchange.
        Fixtures.set_unit_hp(context.world, barbarian.id, 5)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:warrior_hp0, warrior.hp)}
      end

      when_ "my warrior attacks and destroys it", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "my warrior still takes the barbarian's counter-damage computed from pre-combat stats",
            context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        surviving_barbarian =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.barbarian.id,
              do: u

        assert surviving_barbarian == []
        assert warrior.hp < context.warrior_hp0
        {:ok, context}
      end
    end
  end
end
