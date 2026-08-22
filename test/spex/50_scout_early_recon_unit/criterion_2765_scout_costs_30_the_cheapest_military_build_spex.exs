defmodule BrokenOathsSpex.Story952.Criterion2765Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2765 — Scout costs 30 production, cheapest of the military
  buildables (Warrior 40). Read off the city's own production queue
  item cost (`Fixtures.player_cities/2`'s documented `queue` shape:
  `[%{id:, type:, banked:, cost:}]`, head = current), the same
  observable surface the running turn/city loop already exposes.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Scout costs 30 — the cheapest military build" do
    scenario "Scout's queued cost undercuts Warrior's" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "the player queues a Scout", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "scout"
        })

        {:ok, context}
      end

      then_ "the queued Scout's cost is 30", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id,
            do: c

        [item | _] = city.queue
        assert item.cost == 30
        {:ok, Map.put(context, :scout_cost, item.cost)}
      end

      when_ "the player then queues a Warrior behind it", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the Warrior's cost (40) is strictly higher than the Scout's (30)", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id,
            do: c

        [_scout_item, warrior_item] = city.queue
        assert warrior_item.cost == 40
        assert context.scout_cost < warrior_item.cost
        {:ok, context}
      end
    end
  end
end
