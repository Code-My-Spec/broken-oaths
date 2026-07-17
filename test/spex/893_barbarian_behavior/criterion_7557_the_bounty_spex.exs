defmodule BrokenOathsSpex.Story893.Criterion7557Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7557 — defeating a barbarian pays the player a 10-gold
  bounty (per stone_age.md §3.2, "10 gold per kill").

  Barbarian-fixture note: see criterion 7551's moduledoc — this uses a
  REAL camp-spawned warrior, one of the 1-2 camps that spawn already
  inside the player's own territory (criterion 7543), attacked via the
  same "attack" event story 891 (`Game.Combat`) drives player-initiated
  combat through. The "attack" event is implemented now (`Game.attack/4`,
  see `play.ex`'s `handle_event("attack", %{"target_unit_id" => ...})`),
  so this spec no longer needs criterion 7538's crash-safe wrapper —
  called directly and matched on `:ok`, the same "surface a validation
  failure at the source" pattern criterion 7556 (this same story)
  settled on for its own direct action calls.

  Setup-hardening (not in the original contract): warriors and the lord
  used to WALK to the camp's doorstep via `queue_move` + a 40-turn wait
  loop, and the attacking barbarian used to be waited for via a 12-turn
  natural-spawn loop. Producing two warriors still takes real turns (no
  test-only bridge creates a player `Game.Unit` directly — only
  `Fixtures.spawn_barbarian/3` does, and only for `:barbarian_warrior`),
  but `Fixtures.relocate_unit/3` places them (and the lord) on the
  camp's doorstep instantly once produced, and `Fixtures.spawn_barbarian/3`
  (tied to the same REAL, revealed camp, so `Turn`'s barbarian AI loop
  drives it for real — see criterion 7551's moduledoc) places the
  target warrior directly on the camp's own tile, the same
  spawn-location a natural cadence would most commonly produce.
  `clear_tile/2` (below) evicts any real, camp-driven squatter already
  sitting on a tile this criterion needs to place something on exactly
  — the same narrow, documented-bridge status the rest of story 893's
  restructured criteria already established.

  KNOWN LIMITATION (statistical): barbarian warriors have no
  documented test-only HP-setting escape hatch the way
  `Fixtures.set_unit_hp/3` gives player units (story 881's healing
  criteria) — that fixture targets `Game.Unit` records, and barbarian
  warriors are explicitly NOT `Game.Unit` rows (see criterion 7533's
  moduledoc, story 891). Per the story text, barbarian warriors
  (15/15/120) are deliberately stronger than a lone Stone Age warrior
  (10/10/100) — "players lose 1v1" — so this spec throws two
  lord-boosted warriors (each getting the +2 aura, per criterion 7541)
  at a single barbarian across several turn boundaries, giving enough
  combined hits (per criterion 7541's ~20-33 damage band) to clear 120
  HP with a comfortable margin. This is a best-effort, not a
  deterministic guarantee, the same caveat class already normalized by
  criterion 7541's own "KNOWN LIMITATION (statistical)" note.

  Gold is read from the rendered HTML badge (`[data-test='player-gold']`),
  the same surface and exact value criterion 7418 (story 873) already
  established for a fresh spawn's starting 50 gold — nothing in this
  Stone Age MVP spends gold on production (production costs are a
  separate "production points" currency), so 50 is still the correct
  pre-bounty anchor here.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the bounty" do
    scenario "killing a barbarian warrior pays the player 10 gold" do
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

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)}
      end

      given_ "two of my warriors and my lord surround a barbarian warrior at the camp's doorstep",
             context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        for _ <- 1..30, do: Fixtures.advance_turn(context.world)

        [warrior1, warrior2 | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        doorsteps =
          context.world
          |> Fixtures.adjacent_tiles(context.camp_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.city.tile_id))

        [d1, d2, d3 | _] = doorsteps

        for {unit, target} <- [{warrior1, d1}, {warrior2, d2}, {lord, d3}] do
          clear_tile(context.world, target)
          :ok = Fixtures.relocate_unit(context.world, unit.id, target)
        end

        {:ok, context}
      end

      given_ "a barbarian warrior has spawned at the camp, adjacent to my whole party", context do
        clear_tile(context.world, context.camp_tile)
        warrior = Fixtures.spawn_barbarian(context.world, context.camp_tile, context.camp_id)
        {:ok, Map.put(context, :barbarian_id, warrior.id)}
      end

      when_ "my warriors keep attacking it, turn after turn, until it falls", context do
        result =
          Enum.reduce_while(1..6, :attacking, fn _round, :attacking ->
            my_warriors =
              for u <- Fixtures.player_units(context.world, context.user),
                  u.type == :warrior,
                  do: u

            live_attackers = Enum.filter(my_warriors, &(&1.movement > 0))

            for attacker <- live_attackers do
              case BrokenOaths.Game.attack(context.world, context.user, attacker.id, context.barbarian_id) do
                {:ok, _} -> :ok
                # The barbarian may already be dead from an earlier
                # attacker this same round — a stale target is expected,
                # not a bug.
                {:error, :invalid_target} -> :ok
              end
            end

            still_alive =
              context.world
              |> Fixtures.list_camps()
              |> Enum.find(&(&1.id == context.camp_id))
              |> Map.fetch!(:warriors)
              |> Enum.any?(&(&1.id == context.barbarian_id))

            if still_alive do
              Fixtures.advance_turn(context.world)
              {:cont, :attacking}
            else
              {:halt, :dead}
            end
          end)

        {:ok, Map.put(context, :fight_result, result)}
      end

      then_ "the barbarian is destroyed and the player is paid a 10-gold bounty", context do
        assert context.fight_result == :dead,
               "the barbarian outlasted the assault (result: #{inspect(context.fight_result)})"

        assert has_element?(context.play_live, "[data-test='player-gold']", "60")
        {:ok, context}
      end
    end
  end

  # Deliberate, narrow exception, same status as the rest of story 893's
  # restructured criteria (see criterion 7556's own `clear_tile/2`):
  # a real, active camp may have already spawned a warrior of its own
  # onto a tile this criterion needs to place something ELSE on exactly
  # — relocate it out of the way first. A no-op if `tile_id` is clear.
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
