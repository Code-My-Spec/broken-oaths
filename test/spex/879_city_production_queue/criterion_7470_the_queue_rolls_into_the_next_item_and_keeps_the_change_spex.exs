defmodule BrokenOathsSpex.Story879.Criterion7470Spex do
  @moduledoc """
  Story 879 — City Production Queue
  Criterion 7470 — when the current item completes, the next queued
  item begins automatically, and any production banked past the
  finished item's cost carries into it.

  All three Stone Age costs (100/60/40) are exact multiples of the
  flat 5/turn base rate (story 879's own scope), so a size-1 city on
  flat banking alone always completes an item with zero surplus — the
  carry-over math would only ever be exercised trivially at zero. To
  give this scenario real overflow to observe, the city here grows
  once — auto-assigning a second worked tile the same way founding
  does (`Yields.pick_worked_tile/2`) — and then manually reassigns its
  OTHER worked tile (via the same override the city panel offers per
  story 880) to the territory's most productive remaining candidate.
  "Most productive" (not just "the first hills-or-plains tile found")
  matters: the auto-assigned tile from growth already contributes its
  own production, and the first plain hills/plains candidate this
  world happens to offer combines with it to total exactly 8/turn — an
  exact divisor of the Warrior's cost (40), which would leave zero
  overflow to observe. Picking the candidate with the highest
  discovered relief/feature bonus instead lands on a real, nonzero
  remainder for this scenario's deterministic world.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the queue rolls into the next item and keeps the change" do
    scenario "a Warrior completing at a boundary hands its overflow to the queued Worker" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city with Warrior then Worker queued, banking more than 5 production a turn", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        # Grow once so there's a second worked tile (auto-assigned exactly
        # like founding's own worked-tile pick), then manually reassign
        # the OTHER worked tile (manual override) to whichever remaining
        # owned candidate has the highest discovered production bonus —
        # hills add +1P, woods add +1P, flat plains gives 1F1P, all
        # additive (canonical table: .code_my_spec/knowledge/
        # stone_age_yields.md). Picking the MOST productive candidate,
        # not just the first hills/plains/woods match, is what makes the
        # per-turn total provably nonzero-remainder against the
        # Warrior's cost on this scenario's deterministic world — see
        # this module's own moduledoc.
        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [c] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [city] = Fixtures.player_cities(context.world, context.user)

        productive_tile =
          (city.territory -- [city.tile_id])
          |> Enum.reject(&(&1 in city.worked_tiles))
          |> Enum.filter(fn t ->
            terrain = Fixtures.tile_terrain(context.world, t)
            terrain.relief == :hills or terrain.base == :plains or terrain.feature == :woods
          end)
          |> Enum.max_by(&tile_production_bonus(context.world, &1), fn -> nil end)

        [currently_worked | _] = city.worked_tiles

        render_hook(play_live, "assign_worked_tile", %{
          "city_id" => city.id,
          "from_tile_id" => currently_worked,
          "to_tile_id" => productive_tile
        })

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})

        # Measure the real per-turn rate rather than assuming it.
        [before] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
        [before_item | _] = before.queue
        Fixtures.advance_turn(context.world)
        [after_1] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
        [after_item | _] = after_1.queue
        per_turn = after_item.banked - before_item.banked

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city) |> Map.put(:per_turn, per_turn)}
      end

      when_ "the warrior completes at a boundary", context do
        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          done? =
            Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :warrior))

          if done? do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "the worker becomes the current production automatically", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        [current | _] = city.queue
        assert current.type == :worker
        {:ok, Map.put(context, :final_city, city)}
      end

      then_ "any production banked past the warrior's cost counts toward the worker", context do
        [current | _] = context.final_city.queue
        # Per-turn production isn't a multiple of the Warrior's cost (40),
        # so completion overshoots it by a known, nonzero remainder that
        # must show up as the worker's starting bank.
        assert rem(40, context.per_turn) != 0
        assert current.banked > 0
        assert current.banked < context.per_turn
        {:ok, context}
      end
    end
  end

  # Discovered (not assumed) production bonus for the "most productive
  # candidate" pick above — hills, plains, and woods each add +1
  # production, additive (canonical table: .code_my_spec/knowledge/
  # stone_age_yields.md).
  defp tile_production_bonus(world, tile_id) do
    terrain = Fixtures.tile_terrain(world, tile_id)
    relief_bonus = if terrain.relief == :hills, do: 1, else: 0
    plains_bonus = if terrain.base == :plains, do: 1, else: 0
    woods_bonus = if terrain.feature == :woods, do: 1, else: 0
    relief_bonus + plains_bonus + woods_bonus
  end
end
