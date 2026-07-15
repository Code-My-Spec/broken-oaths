defmodule BrokenOathsSpex.Story879.Criterion7468Spex do
  @moduledoc """
  Story 879 — City Production Queue
  Criterion 7468 — every city banks a flat 5 production per turn
  boundary, so a size-1 city's Warrior (40) completes at exactly the
  eighth boundary — not the seventh, not the ninth.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a warrior completes after eight turns of flat banking" do
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

      when_ "seven turn boundaries pass", context do
        for _ <- 1..7, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the warrior is not yet on the map", context do
        refute Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.type == :warrior)
               )

        {:ok, context}
      end

      when_ "the eighth boundary passes", context do
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

      then_ "a ninth boundary was not needed", context do
        # Already true by construction: the warrior above appeared right
        # after the eighth boundary, with no further advance_turn call.
        assert Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.type == :warrior)
               )

        {:ok, context}
      end
    end
  end
end
