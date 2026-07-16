defmodule BrokenOathsSpex.Story878.Criterion7461Spex do
  @moduledoc """
  Story 878 — Settler Founds City
  Criterion 7461 — a settler founds a city on the grassland it stands on.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a settler founds a city on the grassland it stands on" do
    scenario "founding on a grassland tile with no city nearby" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "the player founds a city on their settler's tile", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        # String id on purpose: real phx-value-* params are strings (QA issue 1574d956).
        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        {:ok, Map.put(context, :settler, settler)}
      end

      then_ "a city appears on exactly that tile", context do
        # The fixture world's settler spawns on grassland (seed-derived) —
        # this is what gives the scenario its "grassland it stands on"
        # premise, with no other city anywhere nearby (fresh world).
        assert Fixtures.tile_terrain(context.world, context.settler.tile_id).base == :grassland

        [city] = Fixtures.player_cities(context.world, context.user)
        assert city.tile_id == context.settler.tile_id
        {:ok, context}
      end
    end
  end
end
