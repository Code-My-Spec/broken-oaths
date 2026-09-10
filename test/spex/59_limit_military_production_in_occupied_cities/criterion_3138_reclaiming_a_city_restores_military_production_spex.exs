defmodule BrokenOathsSpex.Story999.Criterion3138Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "reclaiming a city restores military production" do
    scenario "the owner can select a warrior after reclaiming the city" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my city is occupied by a wartime rival", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "the owner reclaims the city", context do
        [owner_lord] =
          for unit <- Fixtures.player_units(context.world, context.other_user), unit.type == :lord, do: unit

        _owner_lord =
          march_to(
            context.other_play_live,
            context.world,
            context.other_user,
            owner_lord,
            context.other_city.tile_id
          )

        render_hook(context.other_play_live, "select_city", %{"city_id" => to_string(context.other_city.id)})
        {:ok, context}
      end

      then_ "military production is available to the restored owner", context do
        assert has_element?(context.other_play_live, "[data-test='production-option-warrior']")
        {:ok, context}
      end
    end
  end
end
