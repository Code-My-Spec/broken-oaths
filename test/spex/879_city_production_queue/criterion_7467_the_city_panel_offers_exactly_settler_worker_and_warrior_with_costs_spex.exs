defmodule BrokenOathsSpex.Story879.Criterion7467Spex do
  @moduledoc """
  Story 879 — City Production Queue
  Criterion 7467 — the Stone Age production catalog is exactly Settler
  (100), Worker (60), Warrior (40); Monument is deferred.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the city panel offers exactly Settler, Worker, and Warrior with costs" do
    scenario "viewing the production choices of a freshly founded city" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player opens their city's panel", context do
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

        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "they view the production choices", context do
        {:ok, context}
      end

      then_ "they see Settler (100), Worker (60), and Warrior (40)", context do
        assert has_element?(context.play_live, "[data-test='production-option-settler']", "100")
        assert has_element?(context.play_live, "[data-test='production-option-worker']", "60")
        assert has_element?(context.play_live, "[data-test='production-option-warrior']", "40")
        {:ok, context}
      end

      then_ "no Monument is offered", context do
        refute has_element?(context.play_live, "[data-test='production-option-monument']")
        {:ok, context}
      end
    end
  end
end
