defmodule BrokenOathsSpex.Story903.Criterion7633Spex do
  @moduledoc """
  Story 903 — Advancing to Bronze Age
  Criterion 7633 — the Bronze Spearman, unlocked by reaching the Bronze
  Age, can defeat a Barbarian Warrior 1v1. Source: stone_age.md §6.2 —
  "Bronze Age unlocks: Bronze Spearman (Strength 18, Defense 18, HP
  120, costs 60 production)" and "Bronze Spearmen can defeat Barbarian
  Warriors 1v1." The Barbarian Warrior's own stats (Strength 15,
  Defense 15, HP 120) come from stone_age.md §3.1, the same baseline
  `BrokenOathsSpex.Story891.Criterion7537Spex`'s moduledoc already
  documents as `Game.Combat.base_strength(:barbarian_warrior)`.

  ## Two missing surfaces

  Reaching the Bronze Age rides on story 902's `TechPanel` — see
  `BrokenOathsSpex.SharedGivens`'s `:player_reached_bronze_age`
  moduledoc for the real `"select_research"` / `"bronze_working_
  confirm"` event flow this given drives. `bronze_spearman` is story
  903's own build target for `BrokenOaths.Cities.Production`'s buildable
  catalog.

  Assumed production-catalog key: `"bronze_spearman"`, the same
  snake_case single-string convention the existing catalog already
  uses (`"warrior"`, `"worker"`, `"settler"`).

  This spec drives the intended, full flow (queue it, wait for it to
  complete, march it into combat, strike repeatedly until one side
  falls) so it exercises the real thing the instant both surfaces
  land, rather than asserting only the current-day refusal.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the Spearman outfights a barbarian", fail_on_error_logs: false do
    scenario "a Bronze Spearman defeats a Barbarian Warrior 1v1" do
      given_(:a_world)
      given_(:registered_player)
      given_(:player_reached_bronze_age)

      given_ "I queue a Bronze Spearman in my city and reconnect to the board", context do
        # The shared given's own view may already be dead (attempting
        # to select Bronze Working crashes it today — see
        # `SharedGivens.player_reached_bronze_age`'s doc); reconnect
        # with a fresh view for this scenario's own action, the same
        # way a player reloading the page would.
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        # Story 911 — the Bronze Spearman now ALSO needs Copper access,
        # a fact independent of this criterion's own subject (combat
        # outcome, not resource placement). `player_reached_bronze_age`
        # founds the city wherever the starting settler happens to
        # land, with no guarantee a real Copper tile sits in its own
        # (small, 7-ish tile) territory — grant it directly, the same
        # "deliberate, narrow test-only exception" class every other
        # `_for_test` fixture already establishes.
        :ok = Fixtures.grant_copper_access(context.world, context.city.id)

        render_hook(play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "bronze_spearman"
        })

        for _ <- 1..15, do: Fixtures.advance_turn(context.world)

        spearman =
          Enum.find(
            Fixtures.player_units(context.world, context.user),
            &(&1.type == :bronze_spearman)
          )

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        my_occupied =
          [context.city.tile_id, lord.tile_id] ++ List.wrap(spearman && spearman.tile_id)

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.city.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, target)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:spearman, spearman)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "my Bronze Spearman strikes the barbarian repeatedly, recharging between blows",
            context do
        outcome =
          if context.spearman do
            Enum.reduce_while(1..10, :fighting, fn i, :fighting ->
              if i > 1, do: Fixtures.recharge_unit(context.world, context.spearman.id)

              attempt_event(context.play_live, "attack", %{
                "unit_id" => context.spearman.id,
                "target_unit_id" => context.barbarian.id
              })

              barbarian_alive? =
                Fixtures.visible_units(context.world, context.user)
                |> Enum.any?(&(&1.id == context.barbarian.id))

              if barbarian_alive?, do: {:cont, :fighting}, else: {:halt, :barbarian_defeated}
            end)
          else
            :no_spearman
          end

        {:ok, Map.put(context, :outcome, outcome)}
      end

      then_ "the barbarian is defeated and my Bronze Spearman survives", context do
        assert context.spearman != nil,
               "no Bronze Spearman exists — production doesn't offer \"bronze_spearman\" yet (story 903) and/or the Bronze Age was never reached"

        assert context.outcome == :barbarian_defeated,
               "the barbarian was still alive after 10 exchanges"

        surviving_spearman =
          Fixtures.player_units(context.world, context.user)
          |> Enum.find(&(&1.id == context.spearman.id))

        assert surviving_spearman != nil, "my Bronze Spearman did not survive the fight"
        assert surviving_spearman.hp > 0

        {:ok, context}
      end
    end
  end
end
