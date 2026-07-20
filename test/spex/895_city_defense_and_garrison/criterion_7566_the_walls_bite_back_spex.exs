defmodule BrokenOathsSpex.Story895.Criterion7566Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7566 — a barbarian that attacks a garrisoned city takes
  counter-attack damage from the garrison, on top of the city itself
  losing HP.

  Judgment calls this spec introduces (both new — nothing in stories
  878-892 attacks a city, only units attack units):

    * The `"attack"` hook (story 891) is extended with a
      `"target_city_id"` param as a sibling to the existing
      `"target_unit_id"` — same hook, same attacker-side `unit_id`,
      just a different kind of target. This is the natural extension
      of the one attack surface this codebase already has, rather than
      a second, parallel hook.
    * "City HP shown in city panel" is explicit story copy (§10.3), so
      HP is read from a new `data-test="city-hp"` element on
      `GameLive.CityPanel`, sibling to `city-defense` (criterion 7562)
      and the existing `city-size`/`city-food`. Later criteria in this
      story (7567, 7568) reuse this same element.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — "the barbarian" is a second real player's warrior.

  No `"target_city_id"` clause exists in `GameLive.Play.handle_event/3`
  yet (story 891's `"attack"` hook only recognizes
  `"target_unit_id"`), so driving it against a city crashes the
  LiveView until `Game.Combat` grows a city-target arm.
  `attempt_attack/2` traps that crash the same way
  `Criterion7533Spex.attempt_attack/3` does, so the RED here is a
  clean `then_` assertion failure instead of an uncaught process
  EXIT; `fail_on_error_logs: false` accepts the resulting GenServer
  crash log for the same reason.

  Setup-hardening (not in the original contract), both real-in-game
  actions rather than new fixtures: (1) each first founding seeds 5-8
  wilderness camps (story 892) — `Fixtures.isolate_camp/2` (the same
  bridge story 893's specs use) keeps only the one farthest from
  either city so no OTHER independently-roaming warrior intercepts
  the marching "barbarian" before it arrives; (2) that march's own
  final step is what spends the barbarian's one movement point
  arriving at `barbarian_target` in the same tick — attacking
  immediately after (no boundary in between) would find it with 0
  movement and be refused, so `Fixtures.recharge_unit/2` restores it
  first. Neither changes what this criterion is actually testing (a
  city takes damage and its garrison counters).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the walls bite back", fail_on_error_logs: false do
    scenario "a barbarian attacking a garrisoned city takes damage back" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my city stands garrisoned by one warrior, with a barbarian adjacent", context do
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

        {:ok, other_join_live, _html} = live(context.other_conn, ~p"/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

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

        # Setup-hardening (not in the original contract): each first
        # founding seeds 5-8 of its own wilderness camps (story 892),
        # 1-2 of them INSIDE the founding player's own claimed region —
        # routinely right next to that player's own city. Over the
        # up-to-40-turn march below, a REAL, independently-roaming
        # warrior from any of THOSE camps can (and for this world's
        # seed, does) intercept and kill the marching "barbarian"
        # (mechanically the second player's own real warrior, per this
        # story's own spec convention) before it ever reaches
        # `barbarian_target` — an unrelated collision this criterion's
        # own SUBJECT (a city takes damage and counters) has no
        # interest in. `Fixtures.isolate_camp/2` (the same sanctioned
        # bridge story 893's specs already use for this exact class of
        # interference) keeps only the single camp farthest from
        # EITHER city and destroys every other camp (from either
        # founding) and its warriors outright.
        [farthest_camp | _] =
          context.world
          |> Fixtures.list_camps()
          |> Enum.sort_by(fn camp ->
            -min(
              mesh_distance(context.world, city.tile_id, camp.tile_id),
              mesh_distance(context.world, other_city.tile_id, camp.tile_id)
            )
          end)

        :ok = Fixtures.isolate_camp(context.world, farthest_camp.id)

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        unless warrior.tile_id == city.tile_id do
          render_hook(play_live, "queue_move", %{
            "unit_id" => to_string(warrior.id),
            "to_tile" => city.tile_id
          })

          Enum.reduce_while(1..10, :ok, fn _, :ok ->
            [w] =
              for u <- Fixtures.player_units(context.world, context.user),
                  u.id == warrior.id,
                  do: u

            if w.tile_id == city.tile_id do
              {:halt, :ok}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)
        end

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id]

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(other_play_live, "queue_move", %{
          "unit_id" => to_string(barbarian.id),
          "to_tile" => barbarian_target
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [b] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == barbarian.id,
                do: u

          if b.tile_id == barbarian_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        # Setup-hardening (not in the original contract): the wait
        # loop above's own arrival tick is what spends the barbarian's
        # one movement point getting it onto `barbarian_target` in the
        # first place (Warrior `max_movement` is 1); attacking in the
        # very same `when_` step with no boundary in between would find
        # it with 0 movement left and be refused (`:out_of_movement`),
        # for a reason that has nothing to do with this criterion's own
        # SUBJECT (a city takes damage and counters). `Fixtures.
        # recharge_unit/2` (already documented, in `WorldServer`, for
        # exactly this "attack right after arrival" shape) restores it
        # without a real boundary passing.
        :ok = Fixtures.recharge_unit(context.world, barbarian.id)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        render_hook(play_live, "select_city", %{"city_id" => to_string(city.id)})
        hp0 = city_hp(play_live)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:city, city)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_hp0, barbarian.hp)
         |> Map.put(:city_hp0, hp0)}
      end

      when_ "the barbarian attacks my city", context do
        result =
          attempt_attack(context.other_play_live, %{
            "unit_id" => to_string(context.barbarian.id),
            "target_city_id" => to_string(context.city.id)
          })

        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "my city loses HP", context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no city-target handler implemented yet)"

        assert city_hp(context.play_live) < context.city_hp0
        {:ok, context}
      end

      then_ "the barbarian takes garrison counter-attack damage", context do
        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.barbarian.id,
              do: u

        assert barbarian.hp < context.barbarian_hp0
        {:ok, context}
      end
    end
  end

  # Re-renders the (already-selected) city panel and extracts the
  # integer shown in `data-test="city-hp"` — `nil` if that element
  # doesn't exist yet (`GameLive.CityPanel` doesn't render city HP
  # until this story lands), so callers see a clean comparison
  # failure in `then_` instead of a setup-phase MatchError.
  defp city_hp(play_live) do
    html = render(play_live)

    case Regex.run(~r/data-test="city-hp"[^>]*>(\d+)/, html) do
      [_, hp] -> String.to_integer(hp)
      nil -> nil
    end
  end

  # See moduledoc — traps the expected crash from driving the
  # not-yet-implemented city-target "attack" event.
  defp attempt_attack(live_view, payload) do
    original_trap = Process.flag(:trap_exit, true)

    result =
      try do
        render_hook(live_view, "attack", payload)
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

  # Raw mesh-adjacency BFS distance from `from` to `to` — the same
  # notion `BrokenOaths.Combat.Camps.ring_band/3` places camps by, used
  # here only to rank camps by "how far from the action," not to
  # validate any land-path route.
  defp mesh_distance(world, from, to, max_depth \\ 40) do
    0..max_depth
    |> Enum.reduce_while({[from], MapSet.new([from])}, fn depth, {frontier, seen} ->
      if to in frontier do
        {:halt, {:found, depth}}
      else
        next =
          frontier
          |> Enum.flat_map(&BrokenOathsSpex.Fixtures.adjacent_tiles(world, &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))

        {:cont, {next, MapSet.union(seen, MapSet.new(next))}}
      end
    end)
    |> case do
      {:found, depth} -> depth
      _ -> 999
    end
  end
end
