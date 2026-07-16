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
end
