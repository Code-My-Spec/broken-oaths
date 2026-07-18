defmodule BrokenOathsSpex.Story907.Criterion7671Spex do
  @moduledoc """
  Story 907 — Automatic Vassalization
  Criterion 7671 — subjugation is not elimination: "the vassal keeps
  playing fully (move, build, grow, research)" (`.code_my_spec/
  knowledge/feudal_vassalage_design.md`, §B). This is the design's own
  retention pillar ("a vassal is a co-author of a political drama
  starting from behind — never a corpse") turned into an acceptance
  test: after becoming a vassal, the SAME ordinary `GameLive.Play`
  commands (move a unit, queue production) that worked before capture
  still work afterward.

  `Game.queue_move/4` and `Game.queue_production/4` have no vassalage
  concept to gate on at all today, so — like
  `BrokenOathsSpex.Story906.Criterion7663Spex`'s own "peacetime"
  criterion — this half is expected to already work; this spec is
  `BrokenOaths.Game.Vassalization`'s own regression guard that becoming
  a vassal must never lock a player out of their own civilization,
  alongside its own actual RED signal (that a Vassalage relationship
  exists at all — see `BrokenOathsSpex.Story907.Criterion7666Spex`'s
  own `vassal-status` judgment call).

  The defending Lord is untouched by this scenario's own siege (an
  ungarrisoned city assault never damages the DEFENDER's own units —
  `Game.CityDefense.resolve_attack/4` only ever counters the ATTACKER),
  so it's still alive and free to move after subjugation.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the vassal keeps playing normally after subjugation" do
    scenario "a fresh vassal still moves their Lord and queues production after being subjugated" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I have just subjugated my rival by taking their last free city", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        {my_lord, _broken_city} =
          capture_city(
            context.play_live,
            context.world,
            context.user,
            my_lord,
            context.other_user,
            context.other_city
          )

        [their_lord] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        assert their_lord.hp > 0

        context
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:their_lord, their_lord)
        |> then(&{:ok, &1})
      end

      when_ "the vassal moves their own Lord and queues a new build in their occupied city",
            context do
        vassal_target =
          adjacent_land_tile(context.world, context.their_lord.tile_id, [
            context.other_city.tile_id
          ])

        their_lord =
          march_to(
            context.other_play_live,
            context.world,
            context.other_user,
            context.their_lord,
            vassal_target
          )

        render_hook(context.other_play_live, "queue_production", %{
          "city_id" => to_string(context.other_city.id),
          "item" => "worker"
        })

        {:ok, Map.put(context, :their_lord, their_lord)}
      end

      then_ "the vassal's move order and build order both actually took", context do
        assert context.their_lord.tile_id != context.other_city.tile_id

        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        [current | _] = city_now.queue
        assert current.type == :worker
        {:ok, context}
      end

      then_ "the vassal's own view still shows they're sworn to their lord", context do
        assert has_element?(
                 context.other_play_live,
                 "[data-test='vassal-status']",
                 context.user.email
               )

        {:ok, context}
      end
    end
  end
end
