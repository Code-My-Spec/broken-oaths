defmodule BrokenOathsSpex.Story912.Criterion7713Spex do
  @moduledoc """
  Story 912 — City Gold Income
  Criterion 7713 — a landlocked size-4 city earns exactly its own BASE
  gold (`BrokenOaths.Cities.Yields.base_gold/1`, `1 + floor(size/2)` — 3
  at size 4), nothing more: no worked tile contributes any tile gold
  when none of them is Coast.

  Founds on a tile whose own land runs at least 3 rings deep in EVERY
  direction (`landlocked_founding_tile/1`, below) — a real,
  deterministic guarantee that neither the founding ring nor any of
  the (at most 3) growth claims a size-4 Stone Age city can ever make
  will touch Coast, so the size-4 city this drives really IS
  landlocked, not merely lucky. Verified again directly (`then_`
  below) rather than assumed.

  Growing to size 4 uses `SharedGivens.grow_city_to/5` (real turn
  boundaries — no shortcut exists for city growth/production anywhere
  in this codebase, same status every other growth spec already
  documents), then measures ONE further boundary's own treasury gain
  while connected — story 909's own "logged in -> treasury" channel,
  already shipped, is the sanctioned way to observe a per-turn gold
  figure with no dedicated UI surface of its own.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a size-4 landlocked city earns 3 base gold a turn" do
    scenario "growing a landlocked city to size 4 and measuring one turn's treasury gain" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I found deep inland, well away from any coast", context do
        founding_tile = landlocked_founding_tile(context.world)

        refute is_nil(founding_tile),
               "expected a deep-inland founding tile on this fixture's globe"

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

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "the city grows all the way to size 4", context do
        grow_city_to(context.world, context.user, context.city.id, 4)
        {:ok, context}
      end

      then_ "none of its worked tiles is Coast — genuinely landlocked", context do
        [grown] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.city.id,
              do: c

        refute Enum.any?(
                 grown.worked_tiles,
                 &(Fixtures.tile_terrain(context.world, &1).base == :coast)
               )

        assert grown.size == 4
        {:ok, context}
      end

      then_ "one more turn's treasury gain is exactly 3 — the size-4 base, nothing more",
            context do
        treasury0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        assert Fixtures.gold(context.world, context.user) == treasury0 + 3
        {:ok, context}
      end
    end
  end

  defp landlocked_founding_tile(world) do
    Enum.find(0..(Fixtures.tile_count(world) - 1), fn t ->
      Fixtures.tile_class(world, t) == :land and deep_land?(world, t, 3)
    end)
  end

  defp deep_land?(world, start, radius) do
    1..radius
    |> Enum.reduce({MapSet.new([start]), [start]}, fn _, {seen, frontier} ->
      next =
        frontier
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&MapSet.member?(seen, &1))

      {MapSet.union(seen, MapSet.new(next)), next}
    end)
    |> elem(0)
    |> Enum.all?(&(Fixtures.tile_class(world, &1) == :land))
  end
end
