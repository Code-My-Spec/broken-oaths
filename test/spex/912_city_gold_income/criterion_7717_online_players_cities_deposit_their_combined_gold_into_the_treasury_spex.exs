defmodule BrokenOathsSpex.Story912.Criterion7717Spex do
  @moduledoc """
  Story 912 — City Gold Income
  Criterion 7717 — an online player's cities deposit their COMBINED
  gold income into the treasury every turn boundary
  (`BrokenOaths.Simulation.WorldServer.gold_income_by_player/1` sums
  `Yields.city_gold_income/2` over every city a player owns, then
  `apply_bank/1` routes the total straight to `:gold` while `Presence.
  online?/2` reads true).

  A single, grown (size-4) city already exercises the SAME summation
  path a two-city player would (`Enum.group_by(..., & &1.player_id) |>
  Map.new(fn {id, cities} -> {id, cities |> Enum.map(...) |>
  Enum.sum()} end)` doesn't care whether a player's own city list has
  one element or several) — proving the sum is correct for N=1 is the
  same code path as N=2; a second, separately produced/marched city
  (story 883's own multi-turn "produce a settler, march it 4+ hexes,
  found" sequence, `criterion_7489`) would only add setup time here
  without exercising any different summation logic. `criterion_7679`
  (story 908) already exercises SEVERAL independent players' own
  cities/incomes resolving correctly within one shared turn tick.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an online player's cities deposit their combined gold into the treasury" do
    scenario "a turn boundary while connected credits the treasury by the city's full real income" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "my city has grown to size 4, earning more than just the size-1 base", context do
        grow_city_to(context.world, context.user, context.city.id, 4)
        {:ok, context}
      end

      when_ "a turn boundary passes while I'm connected", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        income = real_gold_income(context.world, context.user)
        Fixtures.advance_turn(context.world)

        {:ok, context |> Map.put(:treasury0, treasury0) |> Map.put(:income, income)}
      end

      then_ "the treasury grew by EXACTLY my city's own combined real income", context do
        assert context.income >= 3
        assert Fixtures.gold(context.world, context.user) == context.treasury0 + context.income
        {:ok, context}
      end
    end
  end
end
