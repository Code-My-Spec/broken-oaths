defmodule BrokenOathsSpex.Story899.Criterion7603Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7603 — even once two players have discovered each other
  and are mutually visible, attacking is still refused. Source: story
  899's own description ("No PvP in the Stone Age — friendly fire
  stays disabled; discovery is the gate that turns two strangers into
  potential collaborators") and stone_age.md §8.1 ("No combat between
  players allowed in Stone Age (friendly fire disabled)").

  This is deliberately adjacent to criterion 7542 (story 891, "no
  friendly fire in the Stone Age") rather than a duplicate of it:
  7542 proves the refusal for two players who have never been
  introduced. This criterion proves the SAME refusal still holds after
  the two players are already known to each other — discovery unlocks
  visibility and chat, never combat — with an explicit `then_` step
  confirming the "already known" precondition before the attack is
  ever attempted.

  Setup mirrors 7542's: found a city, produce a warrior for both
  players, wait for production, then use `Fixtures.relocate_unit/3`
  for cross-player adjacency (same documented rationale — avoids a
  long march exposed to real, roaming barbarians per stories 892/893).
  Discovery itself is triggered first, via the players' LORDS (the
  same mechanism criterion 7597 uses), before the warriors are ever
  brought together for the attack attempt.

  Reuses criterion 7542's `attempt_attack/3` helper and its documented
  reasoning: the "attack" event has no handler yet, so calling it
  crashes the LiveView (`FunctionClauseError`) until `Game.Combat`
  handles player-vs-player targets — trapping exits converts that
  crash into an ordinary, assertable result instead of taking down the
  whole test process.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "no attacking a discovered player" do
    scenario "attacking a player I have already discovered is still refused" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my warrior stands ready and the other player is already known to me", context do
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

        # First contact: the two lords meet so the players are
        # genuinely "known" to each other before any attack is ever
        # attempted (mirrors criterion 7597's own trigger).
        lord_occupied = [city.tile_id, lord.tile_id, warrior.tile_id, other_lord.tile_id]

        [lord_meet_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in lord_occupied))

        :ok = Fixtures.relocate_unit(context.world, other_lord.id, lord_meet_tile)
        Fixtures.advance_turn(context.world)

        # Now bring the warriors adjacent for the attack attempt.
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id, lord_meet_tile]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        :ok = Fixtures.relocate_unit(context.world, other_warrior.id, target)

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == other_warrior.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:other_warrior, other_warrior)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:other_warrior_hp0, other_warrior.hp)}
      end

      then_ "the other player already appears in my Known Players list", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}']",
                 context.other_user.email
               )

        {:ok, context}
      end

      when_ "I order an attack on their adjacent unit", context do
        result = attempt_attack(context.play_live, context.warrior.id, context.other_warrior.id)
        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "the attack is refused with a reason, and neither warrior takes damage", context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        assert has_element?(context.play_live, "[data-test='combat-error']")

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.other_warrior.id,
              do: u

        assert warrior.hp == context.warrior_hp0
        assert other_warrior.hp == context.other_warrior_hp0
        {:ok, context}
      end
    end
  end

  # See criterion 7542's (story 891) identical helper and moduledoc
  # note: the "attack" event has no handler yet, so calling it crashes
  # the LiveView as a genuine process EXIT rather than a rescuable
  # value — trapping exits converts that into an ordinary, assertable
  # result.
  defp attempt_attack(live_view, unit_id, target_unit_id) do
    original_trap = Process.flag(:trap_exit, true)

    result =
      try do
        render_hook(live_view, "attack", %{
          "unit_id" => to_string(unit_id),
          "target_unit_id" => to_string(target_unit_id)
        })

        :ok
      rescue
        _ -> :crashed
      catch
        :exit, _ -> :crashed
      end

    result =
      receive do
        {:EXIT, _pid, _reason} -> :crashed
      after
        100 -> result
      end

    Process.flag(:trap_exit, original_trap)
    result
  end
end
