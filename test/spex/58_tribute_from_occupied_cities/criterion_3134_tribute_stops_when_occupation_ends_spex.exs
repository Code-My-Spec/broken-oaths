defmodule BrokenOathsSpex.Story998.Criterion3134Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "tribute stops when occupation ends" do
    scenario "a reclaimed city no longer pays its former occupier" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I occupy the rival's city", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "the original owner reclaims the city", context do
        [owner_lord] =
          for unit <- Fixtures.player_units(context.world, context.other_user), unit.type == :lord, do: unit

        owner_lord =
          march_to(
            context.other_play_live,
            context.world,
            context.other_user,
            owner_lord,
            context.other_city.tile_id
          )

        {:ok, Map.put(context, :owner_lord, owner_lord)}
      end

      then_ "the former occupier no longer sees tribute from that city", context do
        refute has_element?(context.play_live, "[data-test='city-tribute-#{context.other_city.id}']")
        {:ok, context}
      end
    end
  end
end
