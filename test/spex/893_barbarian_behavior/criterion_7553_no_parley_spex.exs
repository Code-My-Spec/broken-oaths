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
  tiles can be equally "1 hex closer"), the player's lord stands on a
  land tile adjacent to the CAMP, and the warrior is placed directly on
  the camp's own tile (the same spawn-location assumption criterion
  7551 documents for a natural spawn) — a deterministic setup for
  "adjacent at the boundary" that needs no guess about pathing.

  Setup-hardening (not in the original contract): the lord used to WALK
  to the camp's doorstep via `queue_move` + a turn-boundary wait loop,
  then wait up to 12 MORE turns for the camp's natural 3-turn spawn
  cadence to produce a warrior — exposing an escort-less lord right at
  a live camp's doorstep for potentially dozens of turns, which is
  exactly the kind of encounter this criterion wants to observe
  DETERMINISTICALLY, not by accident before the scenario's own setup
  finishes. `Fixtures.relocate_unit/3` places the lord at the doorstep
  instantly; `Fixtures.spawn_barbarian/3` (tied to the same REAL,
  revealed camp, so `Turn`'s barbarian AI loop drives it for real —
  see criterion 7551's moduledoc) places the warrior directly, and the
  whole scenario resolves in a single `advance_turn`.

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
         |> Map.put(:camp_tile, camp.tile_id)}
      end

      given_ "the player's lord stands at the camp's doorstep and a warrior stands on the camp",
             context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [doorstep | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.camp_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.city.tile_id))

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        :ok = Fixtures.relocate_unit(context.world, lord.id, doorstep)

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        warrior = Fixtures.spawn_barbarian(context.world, context.camp_tile, context.camp_id)

        # Anchor: the deterministic setup actually holds — the warrior
        # really is adjacent to the lord, not a coincidence the rest of
        # the spec is quietly relying on.
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
