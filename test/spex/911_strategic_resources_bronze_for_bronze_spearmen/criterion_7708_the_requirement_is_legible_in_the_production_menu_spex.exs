defmodule BrokenOathsSpex.Story911.Criterion7708Spex do
  @moduledoc """
  Story 911 — Strategic Resources: Bronze for Bronze Spearmen
  Criterion 7708 — the Copper requirement is legible in the production
  menu on the Bronze Spearman option: it names "Requires Copper" and
  shows whether it's currently MET, in both directions — not just as a
  disabled-reason footnote when it happens to be unmet (criteria
  7704-7706 already cover the underlying ACCESS rule; this criterion's
  own subject is the UI's own legibility, in both states, on the exact
  same city).

  Reuses `SharedGivens.player_reached_bronze_age` (this criterion
  doesn't care WHERE the city lands, unlike 7704-7706's own deliberate
  geometry) to reach the Bronze Age quickly, then flips Copper access
  with `Fixtures.grant_copper_access/2` — the same deliberate, narrow
  test-only fixture `Criterion7633Spex` (story 903) and
  `ReturningLordManagesCityTest` now use to satisfy story 911's own new
  precondition for scenarios whose SUBJECT is something else entirely.
  Here it IS the subject: this scenario asserts on the exact moment
  access flips from absent to present, on the identical city and
  render, isolating the display concern from the placement/access
  geometry `Criterion7704Spex`/`Criterion7706Spex` already own.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the requirement is legible in the production menu" do
    scenario "the Bronze Spearman option names Requires Copper and reflects whether it's met" do
      given_(:a_world)
      given_(:registered_player)
      given_(:player_reached_bronze_age)

      given_ "I reconnect to the board and open my city panel", context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        render_hook(play_live, "select_city", %{"city_id" => context.city.id})

        {:ok, Map.put(context, :play_live, play_live)}
      end

      then_ "the Bronze Spearman option is offered, and its Copper requirement is legible as NOT met", context do
        assert has_element?(context.play_live, "[data-test='production-option-bronze_spearman']")

        assert has_element?(
                 context.play_live,
                 "[data-test='production-option-bronze_spearman'][data-disabled='true']"
               )

        assert has_element?(
                 context.play_live,
                 "[data-test='production-requirement-bronze_spearman'][data-copper-met='false']",
                 "Requires Copper"
               )

        {:ok, context}
      end

      when_ "the city gains Copper access and the panel is reopened", context do
        :ok = Fixtures.grant_copper_access(context.world, context.city.id)

        # Force a fresh mount so this render picks up the just-granted
        # access the same way a real player would see it on their next
        # city-panel open (`refresh_board/1`'s own `copper_access?`
        # recompute rides the SAME `select_city`/mount-time path a real
        # reload or reselection would take — no bespoke "poke it"
        # event exists for this, nor should one).
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        render_hook(play_live, "select_city", %{"city_id" => context.city.id})

        {:ok, Map.put(context, :play_live, play_live)}
      end

      then_ "the Bronze Spearman option is now enabled, and its Copper requirement is legible as MET", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='production-option-bronze_spearman'][data-disabled='false']"
               )

        assert has_element?(
                 context.play_live,
                 "[data-test='production-requirement-bronze_spearman'][data-copper-met='true']",
                 "Requires Copper"
               )

        {:ok, context}
      end
    end
  end
end
