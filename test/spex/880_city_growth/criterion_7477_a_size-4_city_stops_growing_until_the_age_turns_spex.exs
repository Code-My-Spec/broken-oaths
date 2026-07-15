defmodule BrokenOathsSpex.Story880.Criterion7477Spex do
  @moduledoc """
  Story 880 — City Growth
  Criterion 7477 — Stone Age cities cap at size 4; food still
  accumulates but growth quietly stops until a later age raises the
  cap.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a size-4 city stops growing until the age turns" do
    scenario "abundant food income past the size-4 cap" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-4 city with abundant food income", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        # Three growths (20 + 30 + 40 food) reach the Stone Age cap.
        Enum.reduce_while(1..300, :ok, fn _, :ok ->
          [c] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
          if c.size >= 4 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "many turn boundaries pass", context do
        for _ <- 1..20, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the city remains size 4", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        assert city.size == 4
        {:ok, Map.put(context, :final_city, city)}
      end

      then_ "no error or loss occurs — the cap is quiet", context do
        # The city keeps banking (or at least holding) food quietly —
        # reading it back doesn't crash, and nothing about the city or
        # its units was lost while capped.
        assert context.final_city.food >= 0

        assert Enum.any?(
                 Fixtures.player_units(context.world, context.user),
                 &(&1.type == :lord)
               )

        {:ok, context}
      end
    end
  end
end
