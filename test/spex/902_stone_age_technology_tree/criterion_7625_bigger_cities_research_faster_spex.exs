defmodule BrokenOathsSpex.Story902.Criterion7625Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7625 — bigger cities research faster: science income scales
  with population (`BrokenOaths.Game.Research.science_per_turn/1`,
  `2 * size` summed over every city — story 902's own acceptance
  criteria: "Cities generate science based on population: 2 science
  per population per turn"), so a city that grows produces more science
  per turn than it did at its smaller size.

  ## Assumed `BrokenOathsWeb.GameLive.TechPanel` surface contract

  `TechPanel` doesn't exist yet. This spec (and every sibling under
  `test/spex/902_stone_age_technology_tree/`) drives the following
  `data-test` contract, designed to mirror this codebase's existing
  panels (`GameLive.CityPanel`'s progress-bar convention,
  `GameLive.ChatPanel`'s toggle-button convention, and `GameLive.Play`'s
  own `abandon-world`/`confirm_abandon?` two-step confirm flow) closely
  enough that an implementer can build straight to it:

    * `[data-test='tech-tree-button']` — always-visible button in the
      main UI (story 9.1: "Tech button opens technology tree") that
      toggles the panel open/closed. Presentational, bubbling pattern
      like `CityPanel`/`UnitPanel` (a plain `phx-click="toggle_tech_panel"`
      with no `phx-target`) rather than a stateful `@myself`-targeted
      component like `ChatPanel`.
    * `[data-test='tech-panel']` — the panel itself, rendered once open.
    * `[data-test='science-per-turn']` — the player's current total
      science income, shown whenever the panel is open
      (`Research.science_per_turn/1` over every one of the player's
      cities — exactly what this spec drives).
    * One row per tech, in `Research.techs/0` order (`animal_husbandry`,
      `pottery`, `mining`, `bronze_working`):
      - `[data-test='tech-<name>']` — clicking it pushes
        `"select_research"` with `%{"tech" => "<name>"}`. A tech already
        in `completed_techs` renders its row disabled/non-interactive
        (`Research.set_research/2` refuses re-selecting a completed
        tech). Selecting `bronze_working` does NOT call
        `Game.set_research/3` directly — see the confirm flow below.
      - `[data-test='tech-cost-<name>']` — the tech's science cost
        (`Research.cost/1`): 50 / 50 / 75 / 100 respectively.
      - `[data-test='tech-unlock-<name>']` — the tech's unlock/benefit
        description (`Research.unlock_description/1`).
      - `[data-test='tech-completed-<name>']` — present only once that
        tech is in `completed_techs`.
    * `[data-test='research-progress']` — visible whenever a tech is
      selected as `current_research`; text reads `"<Tech Label>
      <banked>/<cost>"` (mirrors `CityPanel`'s `city-production-current`
      "Warrior 25/40" convention).
    * `[data-test='research-progress-bar']` — a `<progress>` element for
      `current_research`, `value=banked max=cost` (mirrors
      `city-production-progress`).
    * `[data-test='bronze-working-warning']` — the confirm modal (same
      `modal modal-open` pattern `Play`'s own `abandon-world` flow
      already uses) shown after clicking `tech-bronze_working`, with
      copy "This will advance you to Bronze Age. Continue?"
      - `[data-test='bronze-working-confirm']` — commits: pushes
        `"bronze_working_confirm"`, the event that actually calls
        `Game.set_research(world, user, :bronze_working)`.
      - `[data-test='bronze-working-cancel']` — pushes
        `"bronze_working_cancel"`, dismissing with nothing selected.

  This spec drives: found a size-1 city, select Animal Husbandry as
  research (2 science/turn at size 1), then grow the SAME city to size 2
  and confirm the panel now shows 4 science/turn — the population
  scaling the criterion names.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "bigger cities research faster" do
    scenario "a city's science income doubles when its population doubles" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player opens the tech panel and researches Animal Husbandry", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})

        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})

        {:ok, context}
      end

      then_ "the size-1 city shows 2 science per turn", context do
        assert has_element?(context.play_live, "[data-test='science-per-turn']", "2")
        {:ok, context}
      end

      when_ "the city grows to size 2", context do
        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == context.city.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "the size-2 city shows 4 science per turn", context do
        assert has_element?(context.play_live, "[data-test='science-per-turn']", "4")
        {:ok, context}
      end
    end
  end
end
