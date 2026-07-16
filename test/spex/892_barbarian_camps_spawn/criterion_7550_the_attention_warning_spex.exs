defmodule BrokenOathsSpex.Story892.Criterion7550Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7550 — founding the player's first city shows a one-time
  warning about barbarian activity: "Your city attracts attention.
  Barbarian camps are forming in the wilderness." (story source:
  `.code_my_spec/stories/stone_age.md` §2.1 — the exact wording; the
  trigger itself was deliberately deferred from story 878 to the
  barbarian stories). "One-time" means later foundings (second city,
  third city, ...) do not repeat it — mirrors criterion 7544's
  "founding an additional city changes nothing about the wilderness"
  and reuses the same real second-founding sequence story 883
  (criterion 7489) established: grow, produce a settler, march it
  4+ hexes, found.

  Rendered HTML (`render/1`, via Phoenix's `<.flash_group>` — see
  `lib/broken_oaths_web/components/layouts.ex`) is the legal surface
  here; this is a one-shot notice, not board/push state, so
  `assert_push_event` doesn't apply.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  @warning "Your city attracts attention. Barbarian camps are forming in the wilderness."

  spex "the attention warning" do
    scenario "the warning shows on the first founding and does not repeat on the second" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "the player founds their first city", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city1] = Fixtures.player_cities(context.world, context.user)

        {:ok, Map.put(context, :city1, city1)}
      end

      then_ "the barbarian warning appears", context do
        assert render(context.play_live) =~ @warning
        {:ok, context}
      end

      then_ "founding a second city does not repeat the warning", context do
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

        # Wilderness camps (story 892) can have real ownerless warriors
        # standing anywhere by now — dozens of turns have passed
        # waiting for growth and settler production; ground-truth
        # camp/warrior tiles (the same sanctioned read criterion 7543
        # uses) are excluded from candidates so a warrior at the
        # city's doorstep can't block every exit.
        barbarian_tiles =
          context.world
          |> Fixtures.list_camps()
          |> Enum.flat_map(fn camp -> [camp.tile_id | Enum.map(camp.warriors, & &1.tile_id)] end)
          |> MapSet.new()

        rings =
          Enum.reduce(1..10, {[context.city1.tile_id], MapSet.new([context.city1.tile_id]), %{}}, fn
            depth, {frontier, seen, by_depth} ->
              next =
                frontier
                |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
                |> Enum.uniq()
                |> Enum.reject(&MapSet.member?(seen, &1))
                |> Enum.filter(land?)

              by_depth = if depth >= 4, do: Map.put(by_depth, depth, next), else: by_depth
              {next, MapSet.union(seen, MapSet.new(next)), by_depth}
          end)
          |> elem(2)

        candidates =
          4..10
          |> Enum.flat_map(&Map.get(rings, &1, []))
          |> Enum.reject(&MapSet.member?(barbarian_tiles, &1))

        # Try candidates in order (nearest first) until one actually
        # queues a path — a tile clear of barbarians can still be
        # unreachable if one blocks the only route to it. Raw integer
        # for `unit_id`: unlike "found_city", "queue_move" never runs
        # it through `Play.parse_id/1`, so a stringified id reads as
        # `:not_owner` and the march never queues at all.
        target =
          Enum.find(candidates, fn candidate ->
            render_hook(context.play_live, "queue_move", %{
              "unit_id" => new_settler.id,
              "to_tile" => candidate
            })

            not has_element?(context.play_live, "[data-test='order-error']")
          end)

        refute target == nil,
               "no land tile 4-10 hexes out had a walkable path (all blocked by barbarians?)"

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

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        cities = Fixtures.player_cities(context.world, context.user)

        # Anchor: the second founding really happened.
        assert length(cities) == 2

        refute render(context.play_live) =~ @warning
        {:ok, context}
      end
    end
  end
end
