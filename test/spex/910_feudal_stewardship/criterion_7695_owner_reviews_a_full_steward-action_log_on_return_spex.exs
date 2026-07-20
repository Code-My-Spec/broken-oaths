defmodule BrokenOathsSpex.Story910.Criterion7695Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7695 — "ANTI-SABOTAGE: every steward action is LOGGED for
  the owner to review on return"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). Two distinct steward actions (a bank sweep, a
  production order) both show up when the owner logs back in — not
  just the most recent one.

  See `criterion_7686`'s own moduledoc for the `subjugate/5` setup, and
  `criterion_7689`/`criterion_7690`'s own `"steward_collect_bank"`/
  `"steward_queue_production"` judgment calls, reused unchanged —
  including reusing `subjugate/5`'s own `vassal_play_live` directly
  (rather than a fresh `live/2` remount) before `go_offline/1`, so a
  stray extra mount never strands the vassal "online" against
  `BrokenOaths.Players.Presence`'s own `:duplicate` Registry keys.

  Reconciled against story 912's REAL gold-income mechanic (QA issue
  589386f2): this spec no longer declares a hand-set income via the
  now-inert `Fixtures.set_player_gold_income/3` seam before the bank
  sweep — the vassal's own real, freshly captured city already earns
  SOME real gold every boundary (`base_gold(1) = 1` at minimum), which
  is all `"steward_collect_bank"` needs to have something to log; this
  criterion is only about the LOG entries themselves, not the amount.

  ## This criterion's own new judgment call: the log itself

  `data-test="steward-log"` on `GameLive.Play`, containing one
  `data-test="steward-log-entry"` per logged action, each naming which
  steward acted (`context.user.email`, the established "identify a
  player" convention — see `BrokenOathsSpex.Story907.Criterion7666Spex`'s
  own moduledoc) — visible only to the OWNER, on their own return.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the owner reviews a full steward-action log on return", fail_on_error_logs: false do
    scenario "both a bank sweep and a production order appear in the returning owner's own log" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my lord stewarded my bank and my production while I was offline", context do
        %{
          lord_play_live: lord_play_live,
          vassal_city: vassal_city,
          vassal_play_live: vassal_play_live
        } =
          subjugate(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(vassal_play_live)

        Fixtures.advance_turn(context.world)

        attempt_event(lord_play_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.other_user.id)
        })

        {:ok, fresh_lord_play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        attempt_event(fresh_lord_play_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.other_user.id),
          "city_id" => to_string(vassal_city.id),
          "item" => "warrior"
        })

        {:ok, context}
      end

      when_ "I log back in", context do
        {:ok, my_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        {:ok, Map.put(context, :my_play_live, my_play_live)}
      end

      then_ "my own steward log shows BOTH actions the lord took while I was away", context do
        assert has_element?(context.my_play_live, "[data-test='steward-log']")

        log_html = render(context.my_play_live)
        entries = Regex.scan(~r/data-test="steward-log-entry"/, log_html)

        assert length(entries) >= 2,
               "expected at least 2 steward-log-entry rows (bank collect + production order), got #{length(entries)}"

        assert log_html =~ context.user.email
        {:ok, context}
      end
    end
  end
end
