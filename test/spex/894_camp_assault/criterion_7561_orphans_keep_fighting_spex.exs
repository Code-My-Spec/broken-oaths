defmodule BrokenOathsSpex.Story894.Criterion7561Spex do
  @moduledoc """
  Story 894 — Camp Assault
  Criterion 7561 — barbarian warriors a camp already spawned are not
  deleted when the camp is destroyed: they remain on the board as live,
  hostile units and are still legal attack targets ("barbarians only
  in the Stone Age" — `combat.spec.md`'s own target-legality rule).

  Surface note: see `BrokenOathsSpex.Story894.Criterion7558Spex`'s
  moduledoc for the inferred `"attack"` + `target_camp_id` surface.
  `Fixtures.list_camps/1` (sanctioned ground truth, same status as
  `region_partition`) is used only to plan the scenario — to know
  *when* a warrior has already spawned and *which* id to track — never
  to assert the outcome. The outcome itself is asserted purely through
  the real "game:units" push (fog-filtered, mirrors "game:cities") and
  a live re-attack through the same `"attack"` hook story 891
  established, exactly the technique criterion 7539 (story 891, "zero
  HP means gone") used to prove a destroyed unit leaves the board —
  mirrored here to prove a surviving one doesn't.

  Ten hits land the killing blow, per the same reasoning as criterion
  7560's moduledoc (criterion 7559 pins a full-HP Warrior at exactly
  10 flat damage per hit, no random roll).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "orphans keep fighting" do
    scenario "a warrior the camp already spawned survives its camp's destruction" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands adjacent to an already-visible barbarian camp", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        assert_push_event(play_live, "game:camps", %{camps: pushed_camps})

        [camp | _] = pushed_camps
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(play_live, "queue_move", %{"unit_id" => warrior.id, "to_tile" => target})

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [w] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id,
              do: u

          if w.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:camp, camp)}
      end

      given_ "the camp has already spawned at least one barbarian warrior", context do
        orphan =
          Enum.reduce_while(1..15, nil, fn _, _ ->
            [camp_now] =
              for c <- Fixtures.list_camps(context.world), c.id == context.camp.id, do: c

            case camp_now.warriors do
              [w | _] ->
                {:halt, w}

              [] ->
                Fixtures.advance_turn(context.world)
                {:cont, nil}
            end
          end)

        refute is_nil(orphan)
        {:ok, Map.put(context, :orphan_id, orphan.id)}
      end

      when_ "my warrior strikes the camp ten times, recharging between each hit, destroying it",
            context do
        for i <- 1..10 do
          render_hook(context.play_live, "attack", %{
            "unit_id" => to_string(context.warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          if i < 10, do: Fixtures.advance_turn(context.world)
        end

        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the camp is destroyed but the previously-spawned warrior still stands on the board",
            context do
        assert_push_event(context.play_live, "game:camps", %{camps: camps_after})
        refute Enum.any?(camps_after, &(&1.id == context.camp.id))

        assert_push_event(context.play_live, "game:units", %{units: units_after})
        orphan_unit = Enum.find(units_after, &(&1.id == context.orphan_id))

        assert orphan_unit != nil
        assert orphan_unit.hp > 0
        {:ok, Map.put(context, :orphan_unit, orphan_unit)}
      end

      then_ "the orphaned warrior is still a legal, hostile attack target", context do
        orphan = context.orphan_unit

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        unless warrior.tile_id == orphan.tile_id or
                 orphan.tile_id in Fixtures.adjacent_tiles(context.world, warrior.tile_id) do
          [bridge | _] =
            context.world
            |> Fixtures.adjacent_tiles(orphan.tile_id)
            |> Enum.filter(&(Fixtures.tile_class(context.world, &1) == :land))

          render_hook(context.play_live, "queue_move", %{
            "unit_id" => warrior.id,
            "to_tile" => bridge
          })

          Enum.reduce_while(1..40, :ok, fn _, :ok ->
            [w] =
              for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id,
                do: u

            if w.tile_id == bridge do
              {:halt, :ok}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)

          # The step above spent the warrior's one point of movement
          # closing the gap (same rule criterion 7536 established) —
          # one more boundary recharges it before the attack below.
          Fixtures.advance_turn(context.world)
        end

        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(warrior.id),
          "target_unit_id" => to_string(orphan.id)
        })

        assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt})
        assert is_integer(dealt) and dealt > 0
        {:ok, context}
      end
    end
  end
end
