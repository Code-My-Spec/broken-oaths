defmodule BrokenOathsSpex.Story906.Criterion7663Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7663 — after capture, "the occupied city keeps running
  under its owner (peacetime rule), so its production queue simply
  continues; the lord skims tribute and does NOT seize production"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-5
  decisions"). This is the "owner runs it, lord skims" design pillar
  (§ System model, "Capture") — the reason a captured player becomes a
  vassal, not a corpse.

  See `criterion_7657`'s own moduledoc for the shared `city-status`
  badge/`grind_city/6` judgment calls, and `criterion_7659`'s own
  moduledoc for why an ungarrisoned besieged city's tile is already
  walkable today with no collision refusal (the ownership change itself
  is what's missing, not the walk).

  This criterion's own subject is narrower than `criterion_7659`'s:
  once occupied, does the ORIGINAL OWNER still fully control the city
  (queue production) through the ordinary `GameLive.Play` surface?
  `Game.queue_production/4` has no occupation concept to gate on at
  all today, so this half is expected to already work — this spec is
  `BrokenOaths.Game.Siege`'s own regression guard that capture must
  never lock the owner out of their own city, alongside its own actual
  RED signal (the `city-status` badge itself).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an occupied city keeps being run by its original owner in peacetime" do
    scenario "the captured city's own owner still queues its production after capture" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I've besieged and walked into an ungarrisoned rival city", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        grind_city(
          context.play_live,
          context.world,
          my_lord,
          context.other_user,
          context.other_city
        )

        my_lord =
          march_to(
            context.play_live,
            context.world,
            context.user,
            my_lord,
            context.other_city.tile_id
          )

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      when_ "the original owner queues a new build in their own occupied city", context do
        render_hook(context.other_play_live, "queue_production", %{
          "city_id" => to_string(context.other_city.id),
          "item" => "worker"
        })

        {:ok, context}
      end

      then_ "the city reads occupied, yet the owner's build order still took", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-status']", "occupied")
        assert has_element?(context.other_play_live, "[data-test='city-production-current']")

        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        [current | _] = city_now.queue
        assert current.type == :worker
        {:ok, context}
      end
    end
  end
end
