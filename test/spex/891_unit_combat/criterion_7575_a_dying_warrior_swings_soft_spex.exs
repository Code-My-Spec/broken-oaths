defmodule BrokenOathsSpex.Story891.Criterion7575Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7575 — a wounded unit fights at reduced effective strength,
  falling linearly from 100% at full HP to 50% near death, and all
  combat math consumes effective strength. A warrior at 20/100 HP
  (effective strength ≈ 10 × (0.5 + 0.5 × 0.2) = 6) should deal
  visibly less damage than an identical warrior at full HP (effective
  strength 10), against identical barbarian opponents.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — both "barbarians" here are mechanically ordinary second-
  player warriors, produced and walked into place through the ordinary
  `GameLive.Play` surface (documented stand-in for story 892,
  `Game.Camps`, which doesn't exist yet). Because both stand-in
  barbarians are plain `:warrior`s with identical stats, they satisfy
  "an identical barbarian" for each side without further engineering.

  The wounded HP is set with `Fixtures.set_unit_hp/3` — the same
  documented, narrow exception story 881's healing criteria already
  rely on.

  KNOWN LIMITATION (statistical): the two damage bands (fresh ~18-31,
  wounded ~16-26, per the formula's own math) overlap, so a single
  random roll per side cannot conclusively separate them the way many
  trials could. This spec asserts the literal, most direct reading of
  "a visibly lower band" — a same-scenario relative comparison
  (wounded < fresh) — plus the individual bands as a secondary sanity
  check.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a dying warrior swings soft" do
    scenario "a wounded warrior's attack lands softer than a fresh one's" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "one warrior at full HP and another at 20 of 100 HP, each attacking an identical barbarian",
             context do
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

        render_hook(other_play_live, "queue_production", %{
          "city_id" => other_city.id,
          "item" => "warrior"
        })

        for _ <- 1..16, do: Fixtures.advance_turn(context.world)

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        [fresh_warrior, wounded_warrior | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [fresh_target_barbarian, wounded_target_barbarian | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        occupied = [city.tile_id, lord.tile_id, fresh_warrior.tile_id, wounded_warrior.tile_id]

        [fresh_target_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(fresh_warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied))

        walk_to(
          context.world,
          other_play_live,
          context.other_user,
          fresh_target_barbarian.id,
          fresh_target_tile
        )

        [wounded_target_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(wounded_warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied ++ [fresh_target_tile]))

        walk_to(
          context.world,
          other_play_live,
          context.other_user,
          wounded_target_barbarian.id,
          wounded_target_tile
        )

        Fixtures.set_unit_hp(context.world, wounded_warrior.id, 20)

        [fresh_barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == fresh_target_barbarian.id,
              do: u

        [wounded_barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == wounded_target_barbarian.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:fresh_warrior, fresh_warrior)
         |> Map.put(:wounded_warrior, wounded_warrior)
         |> Map.put(:fresh_barbarian, fresh_barbarian)
         |> Map.put(:wounded_barbarian, wounded_barbarian)
         |> Map.put(:fresh_barbarian_hp0, fresh_barbarian.hp)
         |> Map.put(:wounded_barbarian_hp0, wounded_barbarian.hp)}
      end

      when_ "both combats resolve", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.fresh_warrior.id),
          "target_unit_id" => to_string(context.fresh_barbarian.id)
        })

        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.wounded_warrior.id),
          "target_unit_id" => to_string(context.wounded_barbarian.id)
        })

        {:ok, context}
      end

      then_ "the wounded warrior's damage comes from a visibly lower band than the fresh warrior's (roughly strength 6 versus strength 10)",
            context do
        [fresh_barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.fresh_barbarian.id,
              do: u

        [wounded_barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.wounded_barbarian.id,
              do: u

        fresh_damage = context.fresh_barbarian_hp0 - fresh_barbarian.hp
        wounded_damage = context.wounded_barbarian_hp0 - wounded_barbarian.hp

        assert wounded_damage < fresh_damage
        assert fresh_damage >= 18 and fresh_damage <= 31
        assert wounded_damage >= 16 and wounded_damage <= 26
        {:ok, context}
      end
    end
  end

  # Walks `unit_id` (owned by `owner`, driven through `live_view`) to
  # `to_tile`, advancing turn boundaries until it arrives — the same
  # immediate-then-recharge movement pattern every other spec in this
  # story relies on.
  defp walk_to(world, live_view, owner, unit_id, to_tile, max_turns \\ 40) do
    render_hook(live_view, "queue_move", %{"unit_id" => unit_id, "to_tile" => to_tile})

    Enum.reduce_while(1..max_turns, :ok, fn _, :ok ->
      [u] = for uu <- Fixtures.player_units(world, owner), uu.id == unit_id, do: uu

      if u.tile_id == to_tile do
        {:halt, :ok}
      else
        Fixtures.advance_turn(world)
        {:cont, :ok}
      end
    end)
  end
end
