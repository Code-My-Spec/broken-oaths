defmodule BrokenOathsSpex.Story996.Criterion3121Spex do
  @moduledoc """
  Story 996 — Conduct a War
  Criterion 3121 — Wartime units cross a rival's territory.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "a wartime unit crosses a rival's territory" do
    scenario "a hostile lord enters the rival city's territory" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      given_ "the rival has founded a city and war has been declared", context do
        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [settler | _] =
          for unit <- Fixtures.player_units(context.world, context.other_user),
              unit.type == :settler,
              do: unit

        render_hook(other_play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [rival_city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(context.play_live, "declare_war", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        [lord | _] =
          for unit <- Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit

        {:ok, context |> Map.put(:lord, lord) |> Map.put(:rival_city, rival_city)}
      end

      when_ "the player orders the lord across the rival's border", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.lord.id),
          "to_tile" => context.rival_city.tile_id
        })

        {:ok, context}
      end

      then_ "the board accepts the hostile border crossing", context do
        assert has_element?(context.play_live, "[data-test='hostile-border-entry']")
        {:ok, context}
      end
    end
  end
end
