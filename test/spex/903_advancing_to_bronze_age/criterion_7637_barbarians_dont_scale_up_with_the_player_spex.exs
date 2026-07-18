defmodule BrokenOathsSpex.Story903.Criterion7637Spex do
  @moduledoc """
  Story 903 — Advancing to Bronze Age
  Criterion 7637 — barbarians keep their Stone Age strength even after
  the player advances to the Bronze Age; the tech advantage belongs
  entirely to the player. Source: stone_age.md §6.2 — "Barbarians
  remain same strength (Bronze Age tech advantage is the point)."

  Rather than reading a barbarian's strength/defense fields directly
  (not exposed on the sanctioned `Fixtures.visible_units/2` shape —
  `id, type, tile_id, hp, max_hp, movement, max_movement, order`, per
  `GameLive.Play`'s own moduledoc), this asserts the SAME evidence
  `BrokenOathsSpex.Story891.Criterion7537Spex` already established for
  the Stone Age baseline: a plain Stone Age Warrior (Strength 10,
  Defense 10) attacking a freshly-spawned Barbarian Warrior lands
  damage in the same ~18-31 band and takes ~27-46 back. If a Bronze Age
  player's barbarians had silently gained strength, those bands would
  shift; landing in the SAME bands after (attempting to) reach the
  Bronze Age is the observable proof the barbarian never scaled.

  Reaching the Bronze Age rides on story 902's `TechPanel` — see
  `BrokenOathsSpex.SharedGivens`'s `:player_reached_bronze_age`
  moduledoc for the real `"select_research"` / `"bronze_working_
  confirm"` event flow this given drives.
  `context.research_select_result` is still asserted directly so a
  future regression in that flow surfaces clearly instead of a
  confusing band mismatch; the combat itself, which is unaffected by
  whether the player's OWN age flip succeeded, is exercised regardless.

  Setup-hardening: same as criterion 7537's own moduledoc — the
  warrior is relocated off its city's tile first so story 895's +50%
  garrison bonus doesn't silently corrupt the plain, no-garrison
  strength-10 band this criterion depends on, and the lord is walked
  away if spawn placement happens to land it adjacent to the warrior
  (`ensure_lord_away/5`, copied from criterion 7537 verbatim) so its
  +2 aura bonus can't do the same.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "barbarians don't scale up with the player", fail_on_error_logs: false do
    scenario "a Stone Age Warrior still trades the same Stone Age damage bands against a barbarian, even after the player reaches the Bronze Age" do
      given_(:a_world)
      given_(:registered_player)
      given_(:player_reached_bronze_age)

      given_ "I reconnect, queue a Stone Age Warrior, and face it off against a fresh barbarian",
             context do
        # The shared given's own view may already be dead (attempting
        # to select Bronze Working crashes it today — see
        # `SharedGivens.player_reached_bronze_age`'s doc); reconnect
        # with a fresh view, the same way a player reloading the page
        # would.
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        render_hook(play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        city_tile = context.city.tile_id

        # See moduledoc's garrison-bonus hardening note (mirrors
        # criterion 7537 exactly): move the warrior off the city tile.
        [warrior_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(city_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [lord.tile_id]))

        :ok = Fixtures.relocate_unit(context.world, warrior.id, warrior_target)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        # See moduledoc's aura-hardening note: spawn placement gives no
        # guarantee the lord doesn't land adjacent to the warrior,
        # which would silently add its +2 aura and push the roll past
        # the plain strength-10 band this criterion asserts.
        lord = ensure_lord_away(context.world, play_live, context.user, lord, warrior.tile_id, city_tile)

        occupied_now = [city_tile, lord.tile_id, warrior.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied_now))

        barbarian = Fixtures.spawn_barbarian(context.world, target)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "the combat resolves", context do
        result =
          attempt_event(context.play_live, "attack", %{
            "unit_id" => context.warrior.id,
            "target_unit_id" => context.barbarian.id
          })

        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "the barbarian still lands in the Stone Age damage band (roughly 18 to 31 dealt, 27 to 46 taken) — unchanged by my own advance to the Bronze Age",
            context do
        assert context.research_select_result == :ok,
               "selecting/confirming Bronze Working as research failed"

        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView"

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        barbarian_damage = context.barbarian_hp0 - barbarian.hp
        warrior_damage = context.warrior_hp0 - warrior.hp

        assert barbarian_damage >= 18 and barbarian_damage <= 31
        assert warrior_damage >= 27 and warrior_damage <= 46
        {:ok, context}
      end
    end
  end

  # If `lord` already stands adjacent to `avoid_tile`, walks it to a
  # free land tile two hexes out and returns the lord's up-to-date
  # unit map; otherwise returns `lord` unchanged. Copied verbatim from
  # `BrokenOathsSpex.Story891.Criterion7537Spex` — see this module's
  # own moduledoc note on why an unplanned aura would corrupt the
  # no-aura band this criterion asserts.
  defp ensure_lord_away(world, live_view, user, lord, avoid_tile, city_tile) do
    ring1 = world |> Fixtures.adjacent_tiles(avoid_tile) |> MapSet.new()

    if MapSet.member?(ring1, lord.tile_id) do
      land? = fn t -> Fixtures.tile_class(world, t) == :land end

      [safe_tile | _] =
        ring1
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&(MapSet.member?(ring1, &1) or &1 in [avoid_tile, city_tile, lord.tile_id]))
        |> Enum.filter(land?)

      render_hook(live_view, "queue_move", %{"unit_id" => lord.id, "to_tile" => safe_tile})

      Enum.reduce_while(1..10, :ok, fn _, :ok ->
        [l] = for u <- Fixtures.player_units(world, user), u.id == lord.id, do: u

        if l.tile_id == safe_tile do
          {:halt, :ok}
        else
          Fixtures.advance_turn(world)
          {:cont, :ok}
        end
      end)

      [l] = for u <- Fixtures.player_units(world, user), u.id == lord.id, do: u
      l
    else
      lord
    end
  end
end
