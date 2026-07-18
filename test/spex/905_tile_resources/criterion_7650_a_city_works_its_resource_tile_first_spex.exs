defmodule BrokenOathsSpex.Story905.Criterion7650Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7650 — a city's citizen auto-assignment prioritizes a
  resource tile over a plainer one. Design doc:
  `.code_my_spec/knowledge/civ6_resources.md` §4 — "the citizen
  auto-assign scorer (2*food + 1*production, story 880) needs no
  change: resource tiles simply score higher and get worked first,
  which is the intended pull" (`BrokenOaths.Game.Yields.
  assignment_score/1`, `pick_worked_tile/2`).

  Rather than relying on chance to land on a spot where a resource
  neighbor happens to outscore its neighbors, this spec SEARCHES the
  world for a founding tile where a resource neighbor's OWN terrain
  score (base + relief + feature, `Yields.tile_yield/1`'s documented
  table — resource-blind on purpose) already strictly beats every one
  of its plain (non-resourced) sibling neighbors. Once the resource's
  own bonus (+1F Cattle/Sheep/Wheat, +1P Stone, `civ6_resources.md`
  §2) stacks on top, that gap can only widen — so if the resource
  tile doesn't end up auto-worked here, the resource system isn't
  pulling citizens toward it as the criterion requires.

  A freshly founded size-1 city has exactly one auto-assigned worked
  tile beyond its free center (story 880 criterion 7476) — the
  smallest, least-ambiguous window to observe "which tile did the
  founding population choose."
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a city works its resource tile first" do
    scenario "a freshly founded city's one worked tile is its resource neighbor, not a plainer one" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a founding spot exists whose resource neighbor outscores every plain neighbor", context do
        {founding_tile, resource_tile} = find_resourced_founding(context.world)

        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:founding_tile, founding_tile)
         |> Map.put(:resource_tile, resource_tile)}
      end

      when_ "the settler walks there and founds a city", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => settler.id,
          "to_tile" => context.founding_tile
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [s] = for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id, do: u

          if s.tile_id == context.founding_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, Map.put(context, :city, city)}
      end

      then_ "the founding population is already working the resource tile", context do
        assert context.city.worked_tiles == [context.resource_tile]
        {:ok, context}
      end
    end
  end

  # Finds `{founding_tile, resource_tile}` such that `resource_tile` is
  # one of `founding_tile`'s land neighbors, carries a resource, and
  # its resource-BLIND terrain score already strictly beats every other
  # (non-resourced) land neighbor's own terrain score — so the
  # resource's own additive bonus can only widen the gap further.
  defp find_resourced_founding(world) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end
    all_land = 0..(Fixtures.tile_count(world) - 1) |> Enum.filter(land?)

    Enum.find_value(all_land, fn founding_tile ->
      neighbors = world |> Fixtures.adjacent_tiles(founding_tile) |> Enum.filter(land?)
      scores = for t <- neighbors, into: %{}, do: {t, terrain_score(Fixtures.tile_terrain(world, t))}

      resourced =
        Enum.filter(neighbors, &(Fixtures.resource_at(world, &1) != nil and scores[&1] != nil))

      plain_scores =
        for t <- neighbors, Fixtures.resource_at(world, t) == nil, scores[t] != nil, do: scores[t]

      max_plain = Enum.max(plain_scores, fn -> -1 end)
      best = Enum.find(resourced, &(scores[&1] > max_plain))

      best && {founding_tile, best}
    end)
  end

  # Resource-blind assignment score (`Yields.assignment_score/1`'s
  # `2*food + production`, over `Yields.tile_yield/1`'s documented
  # base + relief + feature table) — unworkable terrain scores `nil`
  # (never a candidate).
  defp terrain_score(%{relief: :mountains}), do: nil
  defp terrain_score(%{feature: :ice}), do: nil

  defp terrain_score(%{base: base, relief: relief, feature: feature}) do
    {base_food, base_prod} = base_yield(base)
    food = base_food + feature_food_bonus(feature)
    prod = base_prod + relief_bonus(relief) + feature_prod_bonus(feature)
    2 * food + prod
  end

  defp base_yield(:grassland), do: {2, 0}
  defp base_yield(:plains), do: {1, 1}
  defp base_yield(:desert), do: {0, 0}
  defp base_yield(:tundra), do: {1, 0}
  defp base_yield(:snow), do: {0, 0}
  defp base_yield(:coast), do: {1, 0}
  defp base_yield(:ocean), do: {1, 0}

  defp relief_bonus(:hills), do: 1
  defp relief_bonus(_other), do: 0

  defp feature_food_bonus(feature) when feature in [:rainforest, :marsh], do: 1
  defp feature_food_bonus(_other), do: 0

  defp feature_prod_bonus(:woods), do: 1
  defp feature_prod_bonus(_other), do: 0
end
