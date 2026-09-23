defmodule BrokenOathsSpex.Story39.Criterion3639Spex do
  @moduledoc """
  Story 39 — Fortify a unit for a defensive bonus
  Criterion 3639 — issuing an attack clears the acting unit's own
  Fortify stance, including a ranged Shoot (the criterion's own
  "including" clause — Shoot is the Archer's sibling to melee
  `"attack"`, `BrokenOaths.Units.Actions.available(%{type: :archer})`).
  Two scenarios cover both real order-issuing hooks; both reset paths
  are the same single `fortified_turns: 0` write 
  (`BrokenOaths.Combat.Resolver.resolve_attack/4`'s own doc, "same
  reset" for melee and ranged).

  Each scenario is its own `spex` block, not two `scenario`s inside
  one — `given_(:a_world)` always creates a world at the same fixed
  seed (`SharedGivens.a_world/1`), and `SexySpex.spex/3` compiles to a
  single ExUnit test shared by every `scenario` nested inside it, so
  two `given_(:a_world)` calls in that ONE test/transaction collide on
  that seed's unique index. Splitting into two `spex` blocks gives
  each its own ExUnit test and its own sandboxed transaction — the
  same shape every other multi-`given_(:a_world)` file in this suite
  already uses (e.g. criterion 7705, 7630).

  Both fortified attackers strike a real, ownerless barbarian
  (`Fixtures.spawn_barbarian/2`) rather than a second player's unit —
  `hostile?/2` refuses PvP between two real players (story 891,
  criterion 7542), the same reason criterion 7565's own moduledoc gives
  for the identical substitution.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "attacking clears the fortified stance (melee)" do
    scenario "a fortified warrior issues a melee attack" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my fortified warrior stands adjacent to a barbarian", context do
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

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [city.tile_id]))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})
        render_hook(play_live, "fortify", %{"unit_id" => to_string(warrior.id)})

        assert has_element?(play_live, "[data-test='unit-fortified']")

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "the player orders it to attack the barbarian", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "the warrior's fortified stance clears", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.fortified_turns == 0
        {:ok, context}
      end
    end
  end

  spex "attacking clears the fortified stance (ranged Shoot)" do
    scenario "a fortified archer issues a ranged Shoot" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my fortified archer stands adjacent to a barbarian", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        # Archer production is gated on Archery, which this scenario
        # doesn't research — a real, already-fortified Archer is spawned
        # directly instead (`Fixtures.spawn_unit/4`, `as: :spawn_unit_for_test`
        # in `WorldServer`), the same sanctioned test-only bypass
        # `spawn_barbarian/2` already uses for the barbarian side of this
        # exchange. `spawn_unit/4`'s `player_id` is the in-game Player
        # row's own id (`Fixtures.join_world/2`), not `context.user.id`
        # — the same distinction criterion 7562's own moduledoc spells out.
        {:ok, player} = Fixtures.join_world(context.world, context.user)
        archer = Fixtures.spawn_unit(context.world, player.id, :archer, city.tile_id)

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(archer.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [city.tile_id]))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(archer.id)})
        render_hook(play_live, "fortify", %{"unit_id" => to_string(archer.id)})

        assert has_element?(play_live, "[data-test='unit-fortified']")

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:archer, archer)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "the player orders it to shoot the barbarian", context do
        render_hook(context.play_live, "shoot", %{
          "unit_id" => to_string(context.archer.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "the archer's fortified stance clears", context do
        [archer] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.archer.id,
              do: u

        assert archer.fortified_turns == 0
        {:ok, context}
      end
    end
  end
end
