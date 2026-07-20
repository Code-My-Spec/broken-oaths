defmodule BrokenOathsSpex.Story912.Criterion7716Spex do
  @moduledoc """
  Story 912 — City Gold Income
  Criterion 7716 — a city's per-turn gold income is recomputed fresh
  every boundary from its CURRENT size/worked tiles
  (`BrokenOaths.Cities.Yields.city_gold_income/2`'s own doc: "recomputed
  fresh every turn boundary [...] never cached on the city itself") —
  so growing raises next turn's income, not merely some later one.

  Deterministic regardless of terrain: `base_gold/1` alone climbs from
  1 (size 1) to a minimum of 3 (size 4) — `tile_gold/1` only ever adds
  a non-negative amount on either side — so a size-4 city's own income
  is ALWAYS strictly greater than a size-1 city's, `1 + coastBonus1
  <= 2 < 3 <= 3 + coastBonus4`, with no dependency on whichever tiles
  this run's own growth happened to claim.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "growing to size 4 raises the city's gold income next turn" do
    scenario "the treasury's own per-turn gain increases once the city reaches size 4" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I measure one turn's treasury gain at size 1", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        size1_income = Fixtures.gold(context.world, context.user) - treasury0

        {:ok, Map.put(context, :size1_income, size1_income)}
      end

      when_ "the city grows all the way to size 4", context do
        grow_city_to(context.world, context.user, context.city.id, 4)
        {:ok, context}
      end

      then_ "the very next turn's treasury gain is strictly bigger than it was at size 1",
            context do
        treasury0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        size4_income = Fixtures.gold(context.world, context.user) - treasury0

        assert size4_income > context.size1_income
        assert size4_income >= 3
        {:ok, context}
      end
    end
  end
end
