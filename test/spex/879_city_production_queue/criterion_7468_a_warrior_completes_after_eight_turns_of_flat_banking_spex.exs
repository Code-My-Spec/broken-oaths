defmodule BrokenOathsSpex.Story879.Criterion7468Spex do
  @moduledoc """
  Story 879 — City Production Queue
  Criterion 7468 — a city's production income is NOT a bare flat 5:
  a freshly founded size-1 city's auto-assigned worked tile
  (`Yields.pick_worked_tile/2`, story 878/880's `persist_found_city!/3`)
  already contributes its own production from turn 0 on top of the
  flat-5 base (`Production.flat_base/0`), and growth to size 2
  (story 880's canonical 20/30/40 thresholds) auto-assigns a second
  worked tile the same way, adding its production from the turn AFTER
  growth lands. On this scenario's deterministic world (`given_(:a_world)`'s
  fixed seed), that real curve is 6/turn for the first four turns (the
  founding tile alone) then 8/turn once the second tile's production
  counts — banking a Warrior (40) complete at exactly the SIXTH
  boundary (24 after turn 4, 32 after turn 5, 40 after turn 6) — not
  the fifth, not the seventh.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a warrior completes after six turns of real per-turn banking" do
    scenario "a size-1 city set to build a Warrior" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-1 city that just set Warrior (40) as production", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        # Freshly founded cities are always size 1 (criterion 7463).
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "five turn boundaries pass", context do
        for _ <- 1..5, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the warrior is not yet on the map", context do
        refute Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.type == :warrior)
               )

        {:ok, context}
      end

      when_ "the sixth boundary passes", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the warrior is complete", context do
        assert Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.type == :warrior)
               )

        {:ok, context}
      end

      then_ "a seventh boundary was not needed", context do
        # Already true by construction: the warrior above appeared right
        # after the sixth boundary, with no further advance_turn call.
        assert Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.type == :warrior)
               )

        {:ok, context}
      end
    end
  end
end
