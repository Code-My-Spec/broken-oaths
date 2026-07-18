defmodule BrokenOathsSpex.Story906.Criterion7665Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7665 — capturing a rival's ONLY (last free) city fires the
  automatic-vassalization trigger (story 907): "capture fires the
  last-free-city check that drives Automatic Vassalization"
  (this story's own description). Story 907 (`Vassalage` relationship,
  the Oath screen, Hidden Agenda) is a LATER requirement in this same
  feudal batch and doesn't exist yet either — this is 906's own
  acceptance test that the TRIGGER fires at capture time, not that 907's
  full vassalage mechanics land here.

  See `criterion_7657`'s own moduledoc for the shared `city-status`
  badge/`grind_city/6` judgment calls, and `criterion_7664`'s own
  moduledoc for the "free" vs "not free" contrast this criterion is the
  positive case of (zero free cities left, this time).

  ## This criterion's own new judgment call: the vassalization signal

  No event/UI shape exists yet for "you've just been vassalized." This
  spec's judgment call, mirroring
  `BrokenOathsSpex.Story896.Criterion7573Spex`'s own equally-unestablished
  `"game:lineage"` push: a pushed `"game:vassalized"` event on the newly
  subjugated player's own view, carrying at minimum a `:message` string
  the player can read. The future implementer is free to rename or
  reshape it (a `lord_player_id`, an Oath-screen redirect, etc.) — what
  "the vassalization trigger fires" requires is that SOME fact reaches
  the vassalized player at the moment their last free city falls.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "occupying the owner's last free city fires the vassalization trigger" do
    scenario "capturing a rival's only city notifies them they've been vassalized" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the rival owns only one city, and I stand adjacent to it, broken and ready", context do
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

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      when_ "I walk my Lord onto their last free city's own tile", context do
        my_lord =
          march_to(
            context.play_live,
            context.world,
            context.user,
            context.my_lord,
            context.other_city.tile_id
          )

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      then_ "my unit actually holds the city's own tile", context do
        assert context.my_lord.tile_id == context.other_city.tile_id
        {:ok, context}
      end

      then_ "the rival is notified their last free city fell and they've been vassalized",
            context do
        assert_push_event(context.other_play_live, "game:vassalized", %{message: message}, 500)
        assert is_binary(message) and message != ""
        {:ok, context}
      end
    end
  end
end
