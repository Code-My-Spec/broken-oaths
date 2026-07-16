defmodule BrokenOathsSpex.Story896.Criterion7572Spex do
  @moduledoc """
  Story 896 — Lord Leads the Fight
  Criterion 7572 — the lord can never be produced again: no city's
  production catalog offers a Lord entry, at any price.

  The Rule this criterion belongs to also says "the lord can never be
  disbanded" — but no disband action exists anywhere in the game yet,
  for any unit type (`grep -rn "disband" lib` turns up nothing outside
  the story-spec prose). There is no real surface to drive an attempt
  to disband anything, so per the boundaries doctrine (never fake a
  surface that doesn't exist) that half of the Rule has no spec here.
  This matches the story's own Three Amigos Gherkin, which gives this
  criterion exactly one scenario and it only exercises the catalog.

  The catalog check is exhaustive rather than a single absence check —
  "at any price" — to prove there is genuinely no Lord option
  anywhere in the rendered catalog, not just that one particular
  price point is missing.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "no second crown" do
    scenario "the production catalog never offers a Lord, at any price" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I founded a city and opened its production catalog", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "I open the city's production catalog", context do
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})
        {:ok, context}
      end

      then_ "no Lord entry exists at any price", context do
        assert has_element?(context.play_live, "[data-test='city-panel']")

        # Anchors — the catalog genuinely rendered its real options, so
        # the absence checked below isn't just an empty page.
        assert has_element?(context.play_live, "[data-test='production-option-settler']")
        assert has_element?(context.play_live, "[data-test='production-option-worker']")
        assert has_element?(context.play_live, "[data-test='production-option-warrior']")

        refute has_element?(context.play_live, "[data-test='production-option-lord']")

        catalog_html =
          context.play_live
          |> element("[data-test='city-panel']")
          |> render()

        refute catalog_html =~ "Lord"

        {:ok, context}
      end
    end
  end
end
