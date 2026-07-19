defmodule BrokenOathsSpex.Story912.Criterion7715Spex do
  @moduledoc """
  Story 912 — City Gold Income
  Criterion 7715 — a coastal size-4 city's worked Coast tiles add their
  own gold on TOP of the size-4 base — `BrokenOaths.Game.Yields.
  tile_gold/1`'s own +1-per-worked-Coast-tile rule stacking additively
  with `base_gold/1`, the same "base + bonus" shape every other yield
  in that module already follows.

  Isolates ONE worked Coast tile's own contribution the same way story
  905's own `criterion_7646` isolates a Cattle tile's food contribution
  (that spec's own moduledoc: "unassign it, measure one turn's [...]
  delta, assign it, measure another turn [...], and subtract — the
  difference is exactly what that ONE tile contributes, independent of
  whatever terrain the founding/center tile itself happens to be"),
  applied here to GOLD via the treasury (story 909's "logged in ->
  treasury" channel) instead of the city's own `food` field.

  Founds on a land tile directly adjacent to a real Coast tile
  (`Production.founding_territory/2`'s own 7-tile founding ring already
  includes every neighbor, water or not — see that function's own doc
  — so the Coast tile is real, claimed territory from turn zero, long
  before growth or any worked-tile reassignment).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a coastal size-4 city adds tile gold to its base" do
    scenario "isolating a worked Coast tile's own +1 gold on a real size-4 city" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I found on land right next to the coast", context do
        # Excludes an iced-over Coast tile (`feature: :ice`, polar
        # water) — `Yields.workable?/1` refuses it, and an unworkable
        # tile can never be assigned to a citizen at all
        # (`WorldServer.validate_assign/4`'s own `:invalid_terrain`
        # refusal), which would silently zero out this spec's own
        # isolated delta.
        coast_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), fn t ->
            terrain = Fixtures.tile_terrain(context.world, t)
            terrain.base == :coast and terrain.feature != :ice
          end)

        refute is_nil(coast_tile),
               "expected at least one workable Coast tile on this fixture's own globe"

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        founding_tile = Fixtures.adjacent_tiles(context.world, coast_tile) |> Enum.find(land?)

        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "queue_move", %{
          "unit_id" => settler.id,
          "to_tile" => founding_tile
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [s] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id, do: u

          if s.tile_id == founding_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:coast_tile, coast_tile)}
      end

      when_ "the city grows all the way to size 4", context do
        grow_city_to(context.world, context.user, context.city.id, 4)
        {:ok, context}
      end

      then_ "the Coast tile's own isolated contribution is exactly +1 gold", context do
        [grown] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.city.id,
              do: c

        assert context.coast_tile in grown.territory
        [some_worked | _] = grown.worked_tiles

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => grown.id,
          "from_tile_id" => some_worked,
          "to_tile_id" => nil
        })

        baseline0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        baseline_income = Fixtures.gold(context.world, context.user) - baseline0

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => grown.id,
          "from_tile_id" => nil,
          "to_tile_id" => context.coast_tile
        })

        measurement0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        with_coast_income = Fixtures.gold(context.world, context.user) - measurement0

        assert with_coast_income - baseline_income == 1
        {:ok, context}
      end
    end
  end
end
