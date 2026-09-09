defmodule BrokenOathsSpex.Story997.Criterion3128Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "occupation preserves city ownership" do
    scenario "the original owner still sees their occupied city" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player

      given_ "I am at war and can occupy the rival city", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [lord] = for unit <- Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit
        target = adjacent_land_tile(context.world, context.other_city.tile_id, [lord.tile_id])
        render_hook(context.play_live, "declare_war", %{"counterparty_user_id" => to_string(context.other_user.id)})
        lord = march_to(context.play_live, context.world, context.user, lord, target)
        {:ok, Map.put(context, :lord, lord)}
      end

      when_ "the occupation begins", context do
        {lord, _city} = capture_city(context.play_live, context.world, context.user, context.lord, context.other_user, context.other_city)
        {:ok, Map.put(context, :lord, lord)}
      end

      then_ "the city remains on its original owner's city panel", context do
        render_hook(context.other_play_live, "select_city", %{"city_id" => to_string(context.other_city.id)})
        assert has_element?(context.other_play_live, "[data-test='city-status']", "occupied")
        assert has_element?(context.other_play_live, "[data-test='city-panel']")
        {:ok, context}
      end
    end
  end
end
