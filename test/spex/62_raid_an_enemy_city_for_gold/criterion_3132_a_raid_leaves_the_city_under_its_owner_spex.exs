defmodule BrokenOathsSpex.Story1002.Criterion3132Spex do
  @moduledoc """
  Story 1002 — Raid an Enemy City for Gold
  Criterion 3132 — a raid leaves the city under its original owner.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a raid leaves the city under its owner" do
    scenario "raiding does not occupy the rival city" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a wartime player can raid the rival city", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        render_hook(context.play_live, "declare_war", %{
          "counterparty_user_id" => to_string(context.other_user.id)
        })

        [lord] = for unit <- Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit
        tile = adjacent_land_tile(context.world, context.other_city.tile_id, [lord.tile_id])
        lord = march_to(context.play_live, context.world, context.user, lord, tile)

        {:ok, Map.put(context, :lord, lord)}
      end

      when_ "the player raids the city", context do
        render_hook(context.play_live, "raid_city", %{
          "unit_id" => to_string(context.lord.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "the original owner still sees the city as free rather than occupied", context do
        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        refute has_element?(context.other_play_live, "[data-test='city-status']")
        {:ok, context}
      end
    end
  end
end
