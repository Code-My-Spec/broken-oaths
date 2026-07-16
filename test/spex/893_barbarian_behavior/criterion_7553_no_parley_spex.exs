defmodule BrokenOathsSpex.Story893.Criterion7553Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7553 — if a player unit is adjacent to a barbarian at a
  turn boundary, the barbarian attacks it automatically; there is no
  diplomacy option, and the player never has to (or gets to) order it.

  Barbarian-fixture note: see criterion 7551's moduledoc — this uses a
  REAL camp-spawned warrior, one of the 1-2 camps that spawn already
  inside the player's own territory (criterion 7543).

  Adjacency-at-spawn, not adjacency-by-chase: rather than predicting
  which tile a hunting barbarian will step onto (ambiguous — several
  tiles can be equally "1 hex closer"), the player's lord is walked
  onto a land tile adjacent to the CAMP first. A freshly spawned
  warrior appears on its camp's own tile (the same spawn-location
  assumption criterion 7551 documents), so the moment it spawns it is
  already adjacent to the lord — a deterministic setup for "adjacent
  at the boundary" that needs no guess about pathing.

  This story owns only the barbarian's decision to attack on sight —
  actual damage-exchange math is story 891's (`Game.Combat`). The
  observable proof used here is the same one story 891 uses
  throughout: the player's own unit loses HP it never spent an order
  on.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "no parley" do
    scenario "a barbarian attacks a player unit standing next to it, unordered" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, revealing a nearby barbarian camp",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [camp | _] = camps0
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)
         |> Map.put(:camp_warrior_baseline_ids, MapSet.new(camp.warriors, & &1.id))}
      end

      given_ "the player's lord marches to the camp's doorstep, before any barbarian exists",
             context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [doorstep | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.camp_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.city.tile_id))

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(lord.id),
          "to_tile" => doorstep
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [l] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

          if l.tile_id == doorstep do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        {:ok, Map.put(context, :lord, lord)}
      end

      given_ "a barbarian warrior spawns right next to the lord", context do
        {warrior, lord} =
          Enum.reduce_while(1..12, {nil, context.lord}, fn _turn, {_warrior, lord} ->
            Fixtures.advance_turn(context.world)
            assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
            camp = Enum.find(camps, &(&1.id == context.camp_id))

            new_warrior =
              Enum.find(camp.warriors, &(&1.id not in context.camp_warrior_baseline_ids))

            [fresh_lord] =
              for u <- Fixtures.player_units(context.world, context.user),
                  u.id == lord.id,
                  do: u

            if new_warrior, do: {:halt, {new_warrior, fresh_lord}}, else: {:cont, {nil, fresh_lord}}
          end)

        # Anchor: the deterministic setup actually holds — the fresh
        # spawn really is adjacent to the lord, not a coincidence the
        # rest of the spec is quietly relying on.
        assert warrior.tile_id in Fixtures.adjacent_tiles(context.world, lord.tile_id)

        {:ok, context |> Map.put(:barbarian, warrior) |> Map.put(:lord, lord) |> Map.put(:lord_hp0, lord.hp)}
      end

      when_ "one more turn boundary passes, with nobody ordering an attack", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the barbarian has attacked my lord without being ordered to", context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.lord.id,
              do: u

        assert lord.hp < context.lord_hp0
        {:ok, context}
      end
    end
  end
end
