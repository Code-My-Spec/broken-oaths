defmodule BrokenOathsSpex.Story901.Criterion7616Spex do
  @moduledoc """
  Story 901 — Cooperative Barbarian Fighting
  Criterion 7616 — once a barbarian camp two allies were fighting
  together is destroyed, its former hex is open ground BOTH of them
  can move into — not just whichever of the two happened to land the
  killing blow (stone_age.md §8.2, "successfully clearing border
  barbarians allows both players to expand").

  Surface note: "opens for expansion" is demonstrated here through
  `"queue_move"` — the same order-issuing hook story 875 established —
  toward the former camp's own tile, for EACH ally's warrior. Story 894
  criterion 7560 already proved a destroyed camp's hex becomes
  ordinary, buildable land for the single player who destroyed it
  (a Worker's Build action becomes legal there); this criterion is
  specifically about the SECOND ally — the one who did NOT land the
  final blow — also being free to move onto that same hex, which is
  the part cooperative destruction adds. `queue_move` is legal to issue
  even with the mover's current-turn movement already spent attacking
  (`WorldServer`'s queue-time check validates ownership/terrain/path,
  not remaining movement — movement is only consumed when the order
  actually executes at a turn boundary), so both allies' attacking
  warriors can immediately be ordered onto the reclaimed hex without
  waiting out a recharge or a real turn boundary first.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "cleared border opens for expansion" do
    scenario "after a shared camp falls to both allies' combined assault, both can move onto its former hex" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "both players have founded cities, and each has a warrior standing beside the same barbarian camp",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        assert_push_event(play_live, "game:camps", %{camps: pushed_camps}, 500)
        [camp | _] = pushed_camps
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

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

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        [other_lord] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        occupied = [city.tile_id, lord.tile_id, other_city.tile_id, other_lord.tile_id]

        [target_a, target_b | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied))

        clear_tile(context.world, target_a)
        :ok = Fixtures.relocate_unit(context.world, warrior.id, target_a)
        clear_tile(context.world, target_b)
        :ok = Fixtures.relocate_unit(context.world, other_warrior.id, target_b)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == other_warrior.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:other_warrior, other_warrior)
         |> Map.put(:camp, camp)}
      end

      when_ "both allies together bring the shared camp down, six hits from one and four from the other",
            context do
        Enum.each(1..6, fn i ->
          render_hook(context.play_live, "attack", %{
            "unit_id" => to_string(context.warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          assert_push_event(context.play_live, "game:combat", %{damage_dealt: _}, 500)
          if i < 6, do: Fixtures.recharge_unit(context.world, context.warrior.id)
        end)

        Fixtures.recharge_unit(context.world, context.other_warrior.id)

        Enum.each(1..4, fn i ->
          render_hook(context.other_play_live, "attack", %{
            "unit_id" => to_string(context.other_warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          assert_push_event(context.other_play_live, "game:combat", %{damage_dealt: _}, 500)
          if i < 4, do: Fixtures.recharge_unit(context.world, context.other_warrior.id)
        end)

        {:ok, context}
      end

      then_ "the shared camp is gone from the board", context do
        assert_push_event(context.other_play_live, "game:camps", %{camps: camps_after}, 500)
        refute Enum.any?(camps_after, &(&1.id == context.camp.id))
        {:ok, context}
      end

      then_ "player one — who never landed the final blow — can now order a move onto the reclaimed hex",
            context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.warrior.id),
          "to_tile" => context.camp.tile_id
        })

        assert_push_event(context.play_live, "game:path", %{unit_id: _, tiles: path}, 500)
        assert path == [context.camp.tile_id]
        {:ok, context}
      end

      then_ "player two — who landed the final blow — can also order a move onto the same reclaimed hex",
            context do
        render_hook(context.other_play_live, "queue_move", %{
          "unit_id" => to_string(context.other_warrior.id),
          "to_tile" => context.camp.tile_id
        })

        assert_push_event(context.other_play_live, "game:path", %{unit_id: _, tiles: path}, 500)
        assert path == [context.camp.tile_id]
        {:ok, context}
      end
    end
  end

  # Deliberate, narrow exception, same status as story 893/894's
  # restructured criteria: a real, active camp may have already spawned
  # a warrior of its own onto a tile this criterion needs to place
  # something ELSE on exactly — relocate it out of the way first. A
  # no-op if `tile_id` is already clear.
  defp clear_tile(world, tile_id) do
    occupant =
      world
      |> Fixtures.list_camps()
      |> Enum.flat_map(& &1.warriors)
      |> Enum.find(&(&1.tile_id == tile_id))

    if occupant do
      parking =
        Fixtures.adjacent_tiles(world, tile_id)
        |> Enum.filter(&(Fixtures.tile_class(world, &1) == :land and &1 != tile_id))

      Enum.find_value(parking, fn t -> Fixtures.relocate_unit(world, occupant.id, t) == :ok end)
    end

    :ok
  end
end
