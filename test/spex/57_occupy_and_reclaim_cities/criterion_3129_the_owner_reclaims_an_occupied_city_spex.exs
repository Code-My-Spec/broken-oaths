defmodule BrokenOathsSpex.Story997.Criterion3129Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "the owner reclaims an occupied city" do
    scenario "the original owner retakes control from a wartime rival" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player

      given_ "my city is occupied by a wartime rival", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [attacker] = for unit <- Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit
        target = adjacent_land_tile(context.world, context.other_city.tile_id, [attacker.tile_id])
        render_hook(context.play_live, "declare_war", %{"counterparty_user_id" => to_string(context.other_user.id)})
        attacker = march_to(context.play_live, context.world, context.user, attacker, target)
        {attacker, _city} = capture_city(context.play_live, context.world, context.user, attacker, context.other_user, context.other_city)

        [owner_lord] = for unit <- Fixtures.player_units(context.world, context.other_user), unit.type == :lord, do: unit
        {:ok, context |> Map.put(:attacker, attacker) |> Map.put(:owner_lord, owner_lord)}
      end

      when_ "I retake control of my occupied city", context do
        owner_lord = march_to(context.other_play_live, context.world, context.other_user, context.owner_lord, context.other_city.tile_id)
        {:ok, Map.put(context, :owner_lord, owner_lord)}
      end

      then_ "my city is reclaimed and no longer occupied by the rival", context do
        assert context.owner_lord.tile_id == context.other_city.tile_id
        render_hook(context.other_play_live, "select_city", %{"city_id" => to_string(context.other_city.id)})
        refute has_element?(context.other_play_live, "[data-test='city-status']", "occupied")
        {:ok, context}
      end
    end
  end
end
