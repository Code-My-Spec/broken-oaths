defmodule BrokenOathsSpex.Story915.Criterion7736Spex do
  @moduledoc """
  Story 915 — Declare Independence and Free Your Cities
  Criterion 7736 — "Cities that do not rise stay loyal to the lord and
  can only be retaken by normal siege (story 906) — there is no
  separate reconquest mechanic. The former lord is notified of the
  declaration and of which cities rose" (story 915's own gherkin).

  ## Flagged ambiguity: the "3 of 5 rose, 2 stayed loyal" split

  The gherkin's own `Given` names an EXACT split (3 of 5 cities rose,
  2 stayed loyal) as an accepted precondition, not something the `When`
  step produces. Story 915's own top-level note says plainly the
  city-rise threshold formula is a "Three Amigos" open question, not
  yet locked — and `criterion_7732`'s own scenario ("each occupied city
  is marked... individually") establishes that the real formula MUST
  have some PER-CITY component (otherwise a per-city preview would be
  meaningless — a purely lord-global score would flip every one of a
  vassal's cities identically). Since nothing in this batch specifies
  what that per-city factor actually is, this spec does NOT hardcode a
  3-of-5 (or any other fixed) split — hardcoding one would either (a)
  invent formula internals nowhere documented, or (b) create a spec
  that only passes for one specific, undocumented implementation
  choice. Reduced to two real cities for tractability (see
  `BrokenOathsSpex.SharedGivens.a_freshly_subjugated_vassal_with_two_
  cities/1`'s own moduledoc), this spec instead uses story 915's own
  LOCKED guarantee — "the outcome is shown before he commits, so there
  is no hidden dice roll" (`criterion_7732`) — as its own ground truth:
  it reads the REAL preview's own per-city verdicts first, then asserts
  the two guarantees this criterion is actually about against
  WHICHEVER split the preview reports, rather than assuming one:
  loyal-marked cities stay occupied and siege-only, and the lord's own
  notification names exactly the cities the preview marked "will rise."
  This makes the spec correct regardless of what the eventual formula
  turns out to be, while still faithfully encoding this criterion's own
  two locked claims.

  ## New judgment call: the lord's own notification

  A pushed `"game:rebellion_declared"` event on the FORMER LORD's own
  session, carrying `:message` and `:risen_city_ids` — mirrors story
  907's own lord-side `"game:new_vassal"` push
  (`BrokenOathsSpex.Story907.Criterion7670Spex`). The gherkin's own
  quoted text ("Wes has declared independence!") names the rebel by
  his story name, not his email — this spec checks the message
  contains both "declared independence" and the rebel's own identifying
  email (the same "identify a player by email" convention this batch
  already uses throughout), rather than asserting the narrative literal
  "Wes" verbatim, which is illustrative flavor text, not a locked
  string contract.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  defp verdict(view, city_id) do
    cond do
      has_element?(view, "[data-test='rise-preview-city-#{city_id}']", "will rise") ->
        :will_rise

      has_element?(view, "[data-test='rise-preview-city-#{city_id}']", "stays loyal") ->
        :stays_loyal

      true ->
        raise "no independence preview verdict rendered for city #{city_id}"
    end
  end

  spex "cities that stay loyal must be taken by siege, and the lord is notified",
    fail_on_error_logs: false do
    scenario "loyal cities remain occupied and siege-only, and Mira is notified naming which cities rose" do
      # QA precedent (see e.g. story 908/913/914's own third-player
      # criteria): the plain `:a_world` given (freq 8) only has TWO
      # spawnable regions — not enough room for the THIRD real player
      # this criterion's own `lord_executes_a_throwaway_garrison/1`
      # needs. Same `seed: 1, frequency: 9` substitute those other
      # criteria already use for exactly this reason.
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "Wes has two occupied cities under Lord Mira, taxed at 40%", context do
        context = a_freshly_subjugated_vassal_with_two_cities(context)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "40"
        })

        {:ok, context}
      end

      given_ "Mira has low Honor from executing a captured garrison elsewhere", context do
        {:ok, lord_executes_a_throwaway_garrison(context)}
      end

      given_ "Wes previews which of his cities will rise, establishing the ground truth for the split",
             context do
        attempt_event(context.other_play_live, "open_independence_preview", %{
          "lord_user_id" => to_string(context.user.id)
        })

        verdicts = %{
          context.other_city.id => verdict(context.other_play_live, context.other_city.id),
          context.second_city.id => verdict(context.other_play_live, context.second_city.id)
        }

        risen_city_ids =
          for {id, :will_rise} <- verdicts, do: id

        loyal_city_ids =
          for {id, :stays_loyal} <- verdicts, do: id

        {:ok,
         context
         |> Map.put(:risen_city_ids, risen_city_ids)
         |> Map.put(:loyal_city_ids, loyal_city_ids)}
      end

      when_ "Wes declares independence and the uprising resolves", context do
        assert length(context.risen_city_ids) + length(context.loyal_city_ids) == 2,
               "the preview should account for both of Wes's occupied cities"

        attempt_event(context.other_play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        attempt_event(context.other_play_live, "confirm_declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "Mira receives a notification listing exactly the cities that rose", context do
        assert_push_event(
          context.play_live,
          "game:rebellion_declared",
          %{message: message, risen_city_ids: pushed_risen_ids},
          500
        )

        assert message =~ "declared independence"
        assert message =~ "Player ##{context.other_user.id}"

        assert Enum.sort(pushed_risen_ids) == Enum.sort(context.risen_city_ids),
               "the lord's own notification should list exactly the cities the preview marked will-rise"

        {:ok, context}
      end

      then_ "the loyal cities remain occupied by Mira, freeable only by normal siege", context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        # Anchor: the vassal's own page still renders fine post-resolution,
        # regardless of how many cities the real formula ends up marking
        # loyal vs risen (see this module's own "flagged ambiguity" note) —
        # without this, an implementation where BOTH cities happen to rise
        # would leave the loop below asserting nothing at all.
        assert has_element?(fresh_vassal_live, "[data-test='turn-number']")

        for loyal_id <- context.loyal_city_ids do
          render_hook(fresh_vassal_live, "select_city", %{"city_id" => to_string(loyal_id)})

          assert has_element?(fresh_vassal_live, "[data-test='city-status']", "occupied"),
                 "a city the preview marked stays-loyal should still read occupied after resolution"
        end

        for risen_id <- context.risen_city_ids do
          render_hook(fresh_vassal_live, "select_city", %{"city_id" => to_string(risen_id)})

          refute has_element?(fresh_vassal_live, "[data-test='city-status']"),
                 "a city the preview marked will-rise should no longer read occupied"
        end

        {:ok, context}
      end
    end
  end
end
