defmodule BrokenOathsSpex.Story906.Criterion7658Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7658 — if a besieger doesn't keep up the pressure, the
  city's own regeneration (`Game.CityDefense.regen/1`, 5 HP/boundary,
  story 895) can outpace the damage already dealt and heal the siege
  before it ever reaches 0 — "the owner or an ally can break the
  siege" (`.code_my_spec/knowledge/feudal_vassalage_design.md` §A).

  Already-implemented mechanic: a hit landed through the immediate
  "attack" surface never suppresses the NEXT boundary's regen
  (`CityDefense`'s own "Regeneration" doc, and `criterion_7567`, story
  895, already covers the barbarian-vs-city case of this same rule).
  This is this story's own acceptance test that the SAME relief applies
  to a PvP siege — one partial hit, then enough quiet turns for regen
  alone to fully heal it back up, never touching `BrokenOaths.Game.Siege`'s
  new "broken" state at all.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "owner relief heals the siege before HP hits zero" do
    scenario "one partial hit followed by quiet turns fully heals the rival city" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my Lord landed one hit on an undefended rival city, well short of breaking it",
             context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        attempt_event(context.play_live, "attack", %{
          "unit_id" => to_string(my_lord.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        [hit_city] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        assert hit_city.hp > 0 and hit_city.hp < 100

        {:ok, Map.put(context, :hit_city, hit_city)}
      end

      when_ "many quiet turns pass with no further assault", context do
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the siege is relieved — the city heals all the way back to full, never broken",
            context do
        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-hp']", "100/100")
        refute has_element?(context.other_play_live, "[data-test='city-status']")
        {:ok, context}
      end
    end
  end
end
