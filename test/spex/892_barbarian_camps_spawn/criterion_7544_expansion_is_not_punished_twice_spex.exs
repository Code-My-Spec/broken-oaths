defmodule BrokenOathsSpex.Story892.Criterion7544Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7544 — founding any city after the first (second, third,
  ...) spawns zero additional barbarian camps. Only the very first
  founding triggers the wilderness (criterion 7543).

  Camp existence has no UI surface until scouted (fog of war,
  criterion 7546), so the before/after comparison here reads
  `Fixtures.list_camps/1`, the same narrow sanctioned ground-truth
  read used by 7543/7546 (see the Fixtures moduledoc). The second
  founding's own effect (a second city existing) IS asserted through
  the real surface (`Fixtures.player_cities/2`, the same sanctioned
  read every other city-loop spec already uses).

  The "grow, produce a settler, march it 4+ hexes, found" sequence
  mirrors story 883's own second-founding criterion (7489) — same
  pattern, reused here because this criterion needs the exact same
  legitimate second founding, just checking a different outcome.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "expansion is not punished twice" do
    scenario "a produced settler founds a second city and no new camps appear" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a first city already stands with its barbarian camps spawned", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [founding_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(founding_settler.id)})
        [city1] = Fixtures.player_cities(context.world, context.user)
        camps_after_first = Fixtures.list_camps(context.world)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city1, city1)
         |> Map.put(:camps_after_first, camps_after_first)}
      end

      given_ "a produced settler marched 4+ hexes from the first city", context do
        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == context.city1.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city1.id),
          "item" => "settler"
        })

        for _ <- 1..20, do: Fixtures.advance_turn(context.world)

        [new_settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        ring4 =
          Enum.reduce(1..4, {[context.city1.tile_id], MapSet.new([context.city1.tile_id])}, fn
            _, {frontier, seen} ->
              next =
                frontier
                |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
                |> Enum.uniq()
                |> Enum.reject(&MapSet.member?(seen, &1))
                |> Enum.filter(land?)

              {next, MapSet.union(seen, MapSet.new(next))}
          end)
          |> elem(0)

        [target | _] = ring4

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(new_settler.id),
          "to_tile" => target
        })

        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          [s] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == new_settler.id,
                do: u

          if s.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [settler] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == new_settler.id,
              do: u

        {:ok, Map.put(context, :settler, settler)}
      end

      when_ "it founds a second city", context do
        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(context.settler.id)})
        {:ok, context}
      end

      then_ "no additional barbarian camps spawn", context do
        camps_after_second = Fixtures.list_camps(context.world)

        # Anchor: the first founding really did spawn camps (5-8, per
        # criterion 7543), so this comparison isn't vacuously "0 == 0".
        assert length(context.camps_after_first) >= 5

        assert camps_after_second == context.camps_after_first
        {:ok, context}
      end

      then_ "a second city exists alongside the first", context do
        cities = Fixtures.player_cities(context.world, context.user)
        assert length(cities) == 2
        {:ok, context}
      end
    end
  end
end
