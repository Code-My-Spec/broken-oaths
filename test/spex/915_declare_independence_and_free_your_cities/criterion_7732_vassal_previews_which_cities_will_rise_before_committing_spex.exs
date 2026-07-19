defmodule BrokenOathsSpex.Story915.Criterion7732Spex do
  @moduledoc """
  Story 915 — Declare Independence and Free Your Cities
  Criterion 7732 — the inspectable-before-committing preview: "each
  occupied city is marked 'will rise' or 'stays loyal'... the outcome
  is shown before he commits, so there is no hidden dice roll to
  surprise him" (story 915's own gherkin) — "No dice-roll feel...
  reputation decides" (`.code_my_spec/knowledge/
  feudal_vassalage_design.md`, "Rebellion batch — LOCKED model").

  ## Judgment call: substituting "5 occupied cities" / Oath Strain "80"

  Reusing `BrokenOathsSpex.SharedGivens.a_freshly_subjugated_vassal_
  with_two_cities/1` — see its own moduledoc for why TWO real cities is
  the tractable substitute for the gherkin's own illustrative "5". The
  Oath Strain figure is likewise substituted the same way
  `BrokenOathsSpex.Story913.Criterion7720Spex`/`Criterion7722Spex`
  already do: six real refused-call-to-arms spikes (already-shipped,
  `+15` each) drive it high without landing on the exact illustrative
  "80" — what matters here is "high grievance," not the literal number.

  ## Judgment call: reaching "Mira has low Honor" for real

  Honor itself has no dedicated numeric UI surface anywhere in this
  codebase (see `BrokenOathsSpex.Story906.Criterion7661Spex`'s own
  moduledoc: "Honor has no observable surface in this batch"). Rather
  than invent a fake Honor-reading badge, this spec drives the ONE
  real, already-shipped action that dents a lord's Honor — executing a
  captured garrison (`BrokenOathsSpex.SharedGivens.
  lord_executes_a_throwaway_garrison/1`) — against a THROWAWAY third
  player, never Wes himself, since Honor is the lord's own
  WORLD-VISIBLE reputation, not a per-relationship figure. The
  DOWNSTREAM, observable effect this criterion actually needs (the
  preview showing "will rise" for Mira's cities) is what gets asserted
  — not a raw Honor number.

  ## New judgment calls this criterion establishes

  1. **The preview event**: `"open_independence_preview"`,
     `%{"lord_user_id" => ...}`, fired on the vassal's own view — driven
     through `attempt_event/3` since no `handle_event/3` clause exists
     yet. Deliberately distinct from `"declare_independence"`
     (`criterion_7731`) — opening the preview commits nothing.
  2. **Per-city verdict marking**: `data-test="rise-preview-city-<city
     id>"`, text content `"will rise"` or `"stays loyal"`, one per
     occupied city, inside a `data-test="independence-preview"` wrapper.
  3. **The army-size preview**: `data-test="rebellion-army-preview"`,
     a plain non-negative integer — the predicted size of the temporary
     rebellion army Wes's own grievance would raise.
  4. **No commit happens from opening the preview alone** — this
     spec's own THIRD `then_` asserts the Vassalage/occupation state is
     completely unchanged after only opening the preview, proving it is
     read-only inspection, not a side-effecting action.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  defp verdict(view, city_id) do
    cond do
      has_element?(view, "[data-test='rise-preview-city-#{city_id}']", "will rise") ->
        "will rise"

      has_element?(view, "[data-test='rise-preview-city-#{city_id}']", "stays loyal") ->
        "stays loyal"

      true ->
        :not_rendered
    end
  end

  spex "a vassal previews which cities will rise before committing", fail_on_error_logs: false do
    scenario "opening the preview marks each occupied city and shows the predicted army size, without committing anything" do
      # QA precedent (see e.g. story 908/913/914's own third-player
      # criteria): the plain `:a_world` given (freq 8) only has TWO
      # spawnable regions — not enough room for the THIRD real player
      # this criterion's own `lord_executes_a_throwaway_garrison/1`
      # needs, so this substitutes the same `frequency: 9` (>= 3
      # spawnable regions) those other criteria already use for
      # exactly that reason. `seed: 17` is this criterion's own
      # additional pick, verified against `Resolution.city_resistance/2`
      # (a stable, deterministic function of seed + tile id, never live
      # RNG — see that module's own moduledoc): the SAME dishonor/
      # tribute this scenario's own given_ steps produce (Honor 98,
      # 40% tribute -> tyranny score 21) clears BOTH of Wes's two real
      # city tiles' own resistance under this seed, matching "both
      # cities rise" — any seed with >= 3 spawnable regions works
      # mechanically; this ONE additionally satisfies that outcome.
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 17, frequency: 9}))}
      end
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "Wes is Mira's vassal with two occupied cities, taxed at 40%", context do
        context = a_freshly_subjugated_vassal_with_two_cities(context)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "40"
        })

        {:ok, context}
      end

      given_ "Mira has already executed a captured garrison elsewhere, denting her world-visible Honor",
             context do
        {:ok, lord_executes_a_throwaway_garrison(context)}
      end

      given_ "Wes's grievance against Mira is high, driven by repeated refused calls to arms",
             context do
        for _ <- 1..6 do
          attempt_event(context.play_live, "issue_levy", %{
            "vassal_user_id" => to_string(context.other_user.id),
            "target_user_id" => to_string(context.third_user.id),
            "share" => "0.5"
          })

          attempt_event(context.other_play_live, "refuse_levy", %{
            "lord_user_id" => to_string(context.user.id)
          })
        end

        {:ok, context}
      end

      when_ "Wes opens the Declare Independence preview", context do
        attempt_event(context.other_play_live, "open_independence_preview", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "each occupied city is marked, and Mira's low Honor plus heavy tribute mark both as will-rise",
            context do
        verdict1 = verdict(context.other_play_live, context.other_city.id)
        verdict2 = verdict(context.other_play_live, context.second_city.id)

        assert verdict1 in ["will rise", "stays loyal"],
               "expected a rendered rise/stay verdict for city #{context.other_city.id}, got #{inspect(verdict1)}"

        assert verdict2 in ["will rise", "stays loyal"],
               "expected a rendered rise/stay verdict for city #{context.second_city.id}, got #{inspect(verdict2)}"

        assert verdict1 == "will rise" and verdict2 == "will rise",
               "a dishonorable, heavily-taxing lord's cities should flock back — expected both of Wes's " <>
                 "two occupied cities marked will-rise, got #{verdict1}/#{verdict2}"

        {:ok, context}
      end

      then_ "the preview shows the predicted size of the temporary rebellion army his grievance will raise",
            context do
        assert has_element?(context.other_play_live, "[data-test='rebellion-army-preview']")

        html = render(context.other_play_live)

        [size_text] =
          Regex.run(~r/data-test="rebellion-army-preview"[^>]*>(\d+)/, html,
            capture: :all_but_first
          )

        size = String.to_integer(size_text)
        assert size > 0, "a strain-driven grievance army preview should be a positive predicted size"

        {:ok, context}
      end

      then_ "the outcome is shown before he commits — opening the preview alone changes nothing yet",
            context do
        refute has_element?(context.other_play_live, "[data-test='at-war-with']"),
               "opening the preview must not itself declare war"

        assert has_element?(
                 context.other_play_live,
                 "[data-test='vassal-status']",
                 context.user.email
               ),
               "Wes should still read as sworn to Mira until he actually commits"

        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-status']", "occupied"),
               "the previewed city should still be occupied — no side effect from previewing alone"

        {:ok, context}
      end
    end
  end
end
