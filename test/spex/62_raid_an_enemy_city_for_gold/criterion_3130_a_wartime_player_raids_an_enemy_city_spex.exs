defmodule BrokenOathsSpex.Story1002.Criterion3130Spex do
  @moduledoc """
  Story 1002 — Raid an Enemy City for Gold
  Criterion 3130 — a wartime player raids an enemy city.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a wartime player raids an enemy city" do
    scenario "a nearby wartime player raids the rival city" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "two players are at war and a Lord can raid the rival city", context do
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

      when_ "the player raids the enemy city", context do
        result = attempt_event(context.play_live, "raid_city", %{
          "unit_id" => to_string(context.lord.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, Map.put(context, :raid_result, result)}
      end

      then_ "the raid is permitted through the city raid surface", context do
        assert context.raid_result == :ok
        refute has_element?(context.play_live, "[data-test='combat-error']")
        {:ok, context}
      end
    end
  end
end
