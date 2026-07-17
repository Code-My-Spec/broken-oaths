defmodule BrokenOathsSpex.Story895.Criterion7568Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7568 — a city reduced to 0 HP is pillaged, not captured:
  it loses one population, its production queue freezes for three
  turn boundaries, and its HP resets to 50 (not 0). The frozen
  production resumes on the fourth boundary from wherever it was
  banked — it does not restart from zero.

  Reuses criterion 7566's `"target_city_id"` attack surface and
  `data-test="city-hp"` element. Grows the city to size 2 first (the
  `City` changeset floors `size` at 1 —
  `lib/broken_oaths/game/city.ex` — so "-1 population" needs a size-2
  starting point to land on an unambiguous, schema-legal size 1
  afterward). No garrison: an undefended city means every attack
  damages the city and none bounces back onto the barbarian, keeping
  the attacker alive across the whole softening loop.

  A Worker (cost 60, no "second citizen to spare" gating unlike
  Settler — see `GameLive.CityPanel.catalog_option/1`) is queued as
  the in-flight production so there is real banked progress for the
  pillage to freeze and later resume. The exact number of hits needed
  to reach 0 HP isn't knowable without `Game.CityDefense` actually
  existing, so the softening loop is bounded generously (25 attacks)
  rather than counted precisely — a documented uncertainty, not a
  fabricated number.

  Setup-hardening (not in the original contract): see criterion
  7566's moduledoc for the full rationale — `Fixtures.isolate_camp/2`
  against an unrelated camp warrior reaching (and killing) the
  attacking barbarian across this criterion's own considerably longer
  wait.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "sacked but still mine" do
    scenario "repeated barbarian attacks pillage the city instead of capturing it" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a size-2 city with a worker mid-build, and an adjacent barbarian ready to attack",
             context do
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

        # Setup-hardening (not in the original contract), a real
        # in-game action rather than a new fixture — see criterion
        # 7566's moduledoc for the full rationale. This criterion's own
        # wait is considerably LONGER (up to 40 marching + 120 growing
        # + 3 queuing turn boundaries before the softening loop even
        # starts, all real ticks the barbarian sits idle through near
        # the city), so the exposure to an unrelated camp warrior is
        # even greater here. `Fixtures.isolate_camp/2` keeps only the
        # camp farthest from either city.
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

        # Let the city grow to size 2 before anything is queued, so no
        # production accrues until the item under test is deliberately
        # queued next.
        Enum.reduce_while(1..120, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == city.id, do: c

        # Setup-hardening (not in the original contract): this
        # criterion's own city regenerates 5 HP on every boundary the
        # softening loop below DOESN'T land a pillaging blow on (see
        # `Game.CityDefense.regen/1` — this loop's attacks are all
        # immediate, out-of-tick resolutions, exactly the class this
        # story's own criterion 7567 requires regen to ignore), so
        # reaching 0 HP from an undefended city's 100 routinely takes
        # well more than the ~8 boundaries a size-2 city's worked-tile
        # production would need to finish ONE Worker (cost 60) —
        # emptying the queue before pillage ever lands, contradicting
        # this criterion's own "there is real banked progress for the
        # pillage to freeze" premise. Un-working the auto-assigned tile
        # (the ordinary `assign_worked_tile` command, same fix
        # criterion 7562 already established) drops accrual to the
        # flat base alone; queuing five Workers back-to-back (instead
        # of one) guarantees a "Worker" item is still in progress
        # whenever pillage actually lands, however many boundaries the
        # softening loop needs (capped at 25, i.e. at most 24 real
        # boundaries of production — nowhere near enough at the flat
        # base to exhaust five).
        case city.worked_tiles do
          [worked | _] ->
            render_hook(play_live, "assign_worked_tile", %{
              "city_id" => to_string(city.id),
              "from_tile_id" => to_string(worked)
            })

          [] ->
            :ok
        end

        for _ <- 1..5 do
          render_hook(play_live, "queue_production", %{
            "city_id" => to_string(city.id),
            "item" => "worker"
          })
        end

        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:city, city)
         |> Map.put(:city_size0, city.size)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "repeated barbarian attacks whittle the city down to 0 HP", context do
        {city_after, hp_at_pillage, banked_at_pillage} =
          Enum.reduce_while(1..25, :ok, fn _, :ok ->
            render_hook(context.other_play_live, "attack", %{
              "unit_id" => to_string(context.barbarian.id),
              "target_city_id" => to_string(context.city.id)
            })

            [c] =
              for cc <- Fixtures.player_cities(context.world, context.user),
                  cc.id == context.city.id,
                  do: cc

            if c.size < context.city_size0 do
              render_hook(context.play_live, "select_city", %{
                "city_id" => to_string(context.city.id)
              })

              {:halt, {c, city_hp(context.play_live), banked_progress(context.play_live)}}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)

        {:ok,
         context
         |> Map.put(:city_after, city_after)
         |> Map.put(:hp_at_pillage, hp_at_pillage)
         |> Map.put(:banked_at_pillage, banked_at_pillage)}
      end

      then_ "the city loses one population", context do
        assert context.city_after.size == context.city_size0 - 1
        {:ok, context}
      end

      then_ "the city's HP resets to 50, not 0", context do
        assert context.hp_at_pillage == 50
        {:ok, context}
      end

      then_ "production makes no progress for the next three turn boundaries", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        assert banked_progress(context.play_live) == context.banked_at_pillage
        {:ok, context}
      end

      then_ "a fourth boundary resumes production from the banked progress, not from zero", context do
        Fixtures.advance_turn(context.world)

        assert banked_progress(context.play_live) > context.banked_at_pillage
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Worker")
        {:ok, context}
      end
    end
  end

  defp city_hp(play_live) do
    html = render(play_live)
    [_, hp] = Regex.run(~r/data-test="city-hp"[^>]*>(\d+)/, html)
    String.to_integer(hp)
  end

  defp banked_progress(play_live) do
    html = render(play_live)

    [_, banked, _cost] =
      Regex.run(~r/data-test="city-production-current"[^>]*>\D*(\d+)\/(\d+)/, html)

    String.to_integer(banked)
  end

  # Raw mesh-adjacency BFS distance from `from` to `to` — the same
  # notion `BrokenOaths.Game.Camps.ring_band/3` places camps by, used
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
