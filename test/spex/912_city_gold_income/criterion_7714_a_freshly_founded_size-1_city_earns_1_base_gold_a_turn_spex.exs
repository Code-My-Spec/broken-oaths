defmodule BrokenOathsSpex.Story912.Criterion7714Spex do
  @moduledoc """
  Story 912 — City Gold Income
  Criterion 7714 — a freshly founded size-1 city earns exactly its own
  base gold (`BrokenOaths.Game.Yields.base_gold/1` — `1 + floor(1/2) =
  1`), nothing more. `found_city` (story 878) already auto-assigns a
  size-1 city's one citizen to its best-scoring adjacent tile
  (`Yields.pick_worked_tile/2`), so this unassigns it first — the same
  `"assign_worked_tile"` event story 905's own `criterion_7646` already
  drives — guaranteeing a genuinely unworked city regardless of
  whatever terrain happened to surround this run's own spawn point,
  rather than assuming the auto-pick never lands on a gold-yielding
  Coast tile.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a freshly founded size-1 city earns 1 base gold a turn" do
    scenario "an unworked size-1 city's treasury grows by exactly 1 gold each turn" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the city has no worked tile at all — base gold only", context do
        case context.city.worked_tiles do
          [worked | _] ->
            render_hook(context.play_live, "assign_worked_tile", %{
              "city_id" => context.city.id,
              "from_tile_id" => worked,
              "to_tile_id" => nil
            })

          [] ->
            :ok
        end

        [city] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.city.id,
              do: c

        assert city.worked_tiles == []
        assert city.size == 1

        {:ok, context}
      end

      when_ "a turn boundary passes", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :treasury0, treasury0)}
      end

      then_ "the treasury grew by exactly 1 gold — the size-1 base, no tile gold", context do
        assert Fixtures.gold(context.world, context.user) == context.treasury0 + 1
        {:ok, context}
      end
    end
  end
end
