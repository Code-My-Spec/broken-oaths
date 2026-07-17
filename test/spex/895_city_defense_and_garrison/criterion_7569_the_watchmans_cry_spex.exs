defmodule BrokenOathsSpex.Story895.Criterion7569Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7569 — the player is alerted twice: once when a barbarian
  closes to within 3 hexes of a city, and again when that barbarian
  actually attacks it. Story copy (§3.3, §10.3) gives the literal
  wording for both:

    * "Barbarians approaching [City Name]! 3 hexes away."
    * "Your city [Name] is under attack!"

  Judgment call: per the board doctrine (canvas board, no tile DOM —
  see criterion 7540's identical reasoning for `game:combat`), an
  alert is expected to travel as a pushed client event. This spec's
  call for that event's shape is `"game:alert"` with a `message` key
  carrying the exact copy above, interpolated with the real city name.

  Reuses criterion 7566's `"target_city_id"` attack surface for the
  second half of the scenario.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — "the barbarian" here is mechanically a second real
  player's warrior.

  Setup-hardening (not in the original contract), all real in-game
  actions rather than new fixtures — see criterion 7566's moduledoc
  for the general rationale this criterion shares (same long-march,
  cross-player setup):

    * `Fixtures.isolate_camp/2` against an unrelated camp warrior
      reaching (and killing) the marching barbarian across the up to
      60 boundaries it takes to reach `approach_tile`.
    * The original contract's second `when_` step drives `"attack"`
      straight from `approach_tile` — 3 hexes out, per the FIRST
      `when_`'s own name — never actually adjacent to the city, which
      `CityDefense.validate_attack/3` refuses (`:not_adjacent`), so no
      "under attack" alert would ever fire. This version finishes the
      march to an actual adjacent tile first (same bounded wait
      pattern the rest of this story's specs use), then
      `Fixtures.recharge_unit/2` (that final step is what spends the
      barbarian's own movement arriving) before attacking — genuinely
      exercising "that barbarian THEN attacks the city," which the
      step's own name already promises.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the watchman's cry" do
    scenario "the player is alerted on approach and again on attack" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my city stands founded, with a barbarian marching toward it from afar", context do
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

        # See moduledoc's isolate_camp hardening note.
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

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        # A tile exactly 3 hops from the city, via BFS rings over raw
        # mesh adjacency (the same ring-growing technique criteria
        # 7543/7544 already established).
        ring2 =
          Enum.reduce(1..2, {[city.tile_id], MapSet.new([city.tile_id])}, fn _, {frontier, seen} ->
            next =
              frontier
              |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
              |> Enum.uniq()
              |> Enum.reject(&MapSet.member?(seen, &1))

            {next, MapSet.union(seen, MapSet.new(next))}
          end)
          |> elem(1)

        ring3 =
          ring2
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(ring2, &1))
          |> Enum.filter(land?)

        [approach_tile | _] = ring3

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:city, city)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:approach_tile, approach_tile)}
      end

      when_ "the barbarian marches to a tile exactly 3 hexes from the city", context do
        render_hook(context.other_play_live, "queue_move", %{
          "unit_id" => to_string(context.barbarian.id),
          "to_tile" => context.approach_tile
        })

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [b] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == context.barbarian.id,
                do: u

          if b.tile_id == context.approach_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "I am alerted that barbarians are approaching within 3 hexes", context do
        assert_push_event(context.play_live, "game:alert", %{message: msg})
        assert msg == "Barbarians approaching #{context.city.name}! 3 hexes away."
        {:ok, context}
      end

      when_ "that barbarian then attacks the city", context do
        # See moduledoc's second hardening note: finish the march to
        # an actual adjacent tile (the FIRST `when_` above only gets
        # the barbarian to `approach_tile`, 3 hexes out) before
        # attacking.
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [adjacent_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.city.tile_id)
          |> Enum.filter(land?)

        render_hook(context.other_play_live, "queue_move", %{
          "unit_id" => to_string(context.barbarian.id),
          "to_tile" => adjacent_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [b] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == context.barbarian.id,
                do: u

          if b.tile_id == adjacent_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        :ok = Fixtures.recharge_unit(context.world, context.barbarian.id)

        render_hook(context.other_play_live, "attack", %{
          "unit_id" => to_string(context.barbarian.id),
          "target_city_id" => to_string(context.city.id)
        })

        {:ok, context}
      end

      then_ "I am alerted that my city is under attack", context do
        assert_push_event(context.play_live, "game:alert", %{message: msg})
        assert msg == "Your city #{context.city.name} is under attack!"
        {:ok, context}
      end
    end
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
