defmodule BrokenOathsSpex.Story907.Criterion7670Spex do
  @moduledoc """
  Story 907 — Automatic Vassalization
  Criterion 7670 — "Both players notified" (`.code_my_spec/stories/
  more_stories.md` §7.1) at the moment vassalization fires — a real-time
  PUSH to each of their own sessions, not just a static UI fact a page
  reload happens to reveal (`criterion_7666`'s own subject). This
  criterion is that push-notification mechanic specifically.

  ## This criterion's own new judgment calls

  Mirrors `BrokenOathsSpex.Story896.Criterion7573Spex`'s own
  `"game:lineage"` judgment call (an equally unestablished event
  shape) and `BrokenOathsSpex.Story906.Criterion7665Spex`'s own
  `"game:vassalized"` one (this story depends on that criterion's own
  trigger):

  1. **The vassal's own notification**: a pushed `"game:vassalized"`
     event on the fresh vassal's own view, carrying a `:message`
     string (already established by `criterion_7665`, story 906 — this
     criterion reuses it rather than inventing a second one, since 906
     already committed to that shape for "the trigger fires").
  2. **The lord's own notification**: a pushed `"game:new_vassal"`
     event on the lord's own view, carrying the new vassal's
     `:vassal_user_id` and a `:message` string — the lord-side half of
     "both players notified" that 906's own criterion never covered
     (906 only exercises the VASSAL's side of the trigger).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "both players are notified when vassalization fires" do
    scenario "capturing a rival's last free city pushes a notification to both sessions" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my rival's last free city stands broken, and my Lord is adjacent", context do
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

      when_ "I walk in and capture their last free city", context do
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

      then_ "the fresh vassal's own session is pushed a vassalization notification", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        assert_push_event(context.other_play_live, "game:vassalized", %{message: message}, 500)
        assert is_binary(message) and message != ""
        {:ok, context}
      end

      then_ "the lord's own session is pushed a new-vassal notification", context do
        assert_push_event(
          context.play_live,
          "game:new_vassal",
          %{vassal_user_id: vassal_user_id, message: message},
          500
        )

        assert vassal_user_id == context.other_user.id
        assert is_binary(message) and message != ""
        {:ok, context}
      end
    end
  end
end
