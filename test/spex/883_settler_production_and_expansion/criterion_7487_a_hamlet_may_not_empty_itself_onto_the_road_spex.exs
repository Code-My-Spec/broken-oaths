defmodule BrokenOathsSpex.Story883.Criterion7487Spex do
  @moduledoc """
  Story 883 — Settler Production and Expansion
  Criterion 7487 — a size-1 city cannot select Settler as production
  (it would destroy the city); it becomes selectable once the city
  grows to size 2.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a hamlet may not empty itself onto the road" do
    scenario "Settler is disabled at size 1 and enabled at size 2" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-1 city", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "select_city", %{"city_id" => city.id})

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "the player opens the production choices", context do
        {:ok, context}
      end

      then_ "Settler is disabled with the reason", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='production-option-settler'][data-disabled='true']"
               )

        assert has_element?(context.play_live, "[data-test='production-disabled-reason-settler']")
        {:ok, context}
      end

      then_ "it becomes selectable once the city grows to size 2", context do
        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == context.city.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})

        refute has_element?(
                 context.play_live,
                 "[data-test='production-option-settler'][data-disabled='true']"
               )

        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "settler"
        })

        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        [current | _] = city.queue
        assert current.type == :settler
        {:ok, context}
      end
    end
  end
end
