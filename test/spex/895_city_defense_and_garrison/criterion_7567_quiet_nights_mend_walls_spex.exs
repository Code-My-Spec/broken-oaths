defmodule BrokenOathsSpex.Story895.Criterion7567Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7567 — a city that isn't attacked during a turn boundary
  regenerates 5 HP that boundary.

  Reuses criterion 7566's `"target_city_id"` attack surface and
  `data-test="city-hp"` panel element — see that file's moduledoc for
  both judgment calls. The city takes one real hit first (there is no
  other way to produce a damaged, sub-100 HP city; same rationale as
  criterion 7480's reliance on `Fixtures.set_unit_hp/3` for unit
  healing, except here the damage itself comes through the real
  attack surface rather than a fixture, since `Game.CityDefense` has
  no equivalent HP-setting escape hatch).

  No `"target_city_id"` clause exists in `GameLive.Play.handle_event/3`
  yet, so driving the setup hit crashes the LiveView until
  `Game.Combat` grows a city-target arm; `attempt_attack/2` traps
  that the same way `Criterion7533Spex.attempt_attack/3` and
  `Criterion7566Spex.attempt_attack/2` do. `fail_on_error_logs: false`
  accepts the resulting GenServer crash log for the same reason.

  Setup-hardening (not in the original contract): see criterion 7566's
  moduledoc for the full rationale — this reuses that criterion's
  long-march setup verbatim, so it needs the SAME two real-in-game-action
  fixes (`Fixtures.isolate_camp/2` against unrelated camp interference,
  `Fixtures.recharge_unit/2` against the march's own final step
  spending the attacker's only movement point).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "quiet nights mend walls", fail_on_error_logs: false do
    scenario "an unattacked city regains exactly 5 HP at the next boundary" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my city has already taken one hit from a barbarian and stands unattacked now", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

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

        # Setup-hardening (not in the original contract), both real
        # in-game actions rather than new fixtures — see criterion
        # 7566's moduledoc for the full rationale (this criterion
        # reuses that one's attack surface and shares the same
        # long-march setup): (1) `Fixtures.isolate_camp/2` keeps only
        # the wilderness camp farthest from either city, so no OTHER
        # independently-roaming warrior intercepts the marching
        # "barbarian" before it arrives.
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

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

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

        # (2) that march's own final step is what spends the
        # barbarian's one movement point arriving in the same tick —
        # attacking immediately after (no boundary in between) would
        # find it with 0 movement and be refused.
        :ok = Fixtures.recharge_unit(context.world, barbarian.id)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        attempt_attack(other_play_live, %{
          "unit_id" => to_string(barbarian.id),
          "target_city_id" => to_string(city.id)
        })

        render_hook(play_live, "select_city", %{"city_id" => to_string(city.id)})
        hp_after_hit = city_hp(play_live)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:hp_after_hit, hp_after_hit)}
      end

      when_ "a turn boundary passes with no further attack", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the city regains exactly 5 HP", context do
        assert is_integer(context.hp_after_hit),
               "no \"city-hp\" panel element rendered yet (GameLive.CityPanel doesn't show city HP until this story lands)"

        assert city_hp(context.play_live) == context.hp_after_hit + 5
        {:ok, context}
      end
    end
  end

  # `nil` if `data-test="city-hp"` doesn't exist yet — see moduledoc.
  defp city_hp(play_live) do
    html = render(play_live)

    case Regex.run(~r/data-test="city-hp"[^>]*>\s*(\d+)/s, html) do
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
