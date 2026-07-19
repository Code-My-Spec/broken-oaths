defmodule BrokenOathsSpex.Story915.Criterion7747Spex do
  @moduledoc """
  Story 915 — Declare Independence and Free Your Cities
  Criterion 7747 — declaring independence creates a first-class,
  persisted `Rebellion` record, not a transient event: "a Rebellion
  record is created with status 'active', naming Wes as the rebel and
  Mira as the former lord... it records the contested and risen
  cities, the spawned temporary army, and the start turn" (story 915's
  own gherkin) — "Rebellion is a first-class entity with a lifecycle:
  declared → active → ended... persisted via the WorldServer delta"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2 —
  first-class Rebellion").

  ## Flagged, deliberately untested clause: "later resolution, disband,
  and heir logic all read from that one record"

  This closing clause of the criterion describes a property of a
  LATER story (919, the Rebellion's end/disband/heir logic — see this
  story's own top-of-file note: "This story is the START of the
  rebellion; story 919 is its END"). No disband/heir/resolution surface
  exists anywhere in this codebase yet to observe through, and
  asserting on it here would mean either inventing 919's own contract
  wholesale or fabricating a fake seam this story doesn't own. This
  spec therefore asserts only what IS this criterion's own, testable-
  today half: the record's existence, status, identity, and the fields
  it carries at the moment of creation.

  ## New judgment call: the Rebellion panel

  No Rebellion UI exists anywhere yet. This spec's own judgment call:
  `data-test="rebellion-panel"`, visible on BOTH the rebel's own
  `GameLive.Play` and the former lord's own — mirrors story 907's own
  `vassal-status`/`vassals-list` "both sides see the same relationship"
  convention. Inside it:

    * `data-test="rebellion-status"` → `"active"`
    * `data-test="rebellion-rebel"` → the rebel's own `user.email`
    * `data-test="rebellion-former-lord"` → the former lord's own
      `user.email`
    * `data-test="rebellion-started-turn"` → a digit string, checked
      against the ALREADY-established `data-test="turn-number"` badge
      (`BrokenOathsSpex.Story874.Criterion7419Spex` and many others)
      read immediately before declaring — reusing an existing, real UI
      element rather than inventing a second, redundant turn-tracking
      surface.
    * `data-test="rebellion-army-size"` → a digit string, the spawned
      temporary army's size.
    * `data-test="rebellion-risen-cities"` / `data-test="rebellion-
      contested-cities"` → digit strings, the risen/still-occupied
      city counts, summing to Wes's one occupied city here (a single
      city keeps this criterion's own setup minimal — the rise/stay
      SPLIT itself is `criterion_7732`'s/`criterion_7736`'s own
      subject, not this one's).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "declaring independence opens a tracked rebellion", fail_on_error_logs: false do
    scenario "a Rebellion record naming both parties, with its own fields, is visible to both the rebel and the former lord" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes is a vassal of Lord Mira", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "Wes declares independence", context do
        [turn_before] =
          Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, render(context.other_play_live),
            capture: :all_but_first
          )

        attempt_event(context.other_play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        attempt_event(context.other_play_live, "confirm_declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, Map.put(context, :turn_before, turn_before)}
      end

      then_ "a Rebellion record is created with status active, naming Wes as rebel and Mira as former lord",
            context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        {:ok, fresh_lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        for view <- [fresh_vassal_live, fresh_lord_live] do
          assert has_element?(view, "[data-test='rebellion-panel'] [data-test='rebellion-status']", "active")

          assert has_element?(
                   view,
                   "[data-test='rebellion-panel'] [data-test='rebellion-rebel']",
                   context.other_user.email
                 )

          assert has_element?(
                   view,
                   "[data-test='rebellion-panel'] [data-test='rebellion-former-lord']",
                   context.user.email
                 )
        end

        {:ok, context |> Map.put(:fresh_vassal_live, fresh_vassal_live) |> Map.put(:fresh_lord_live, fresh_lord_live)}
      end

      then_ "it records the contested and risen cities, the spawned temporary army, and the start turn",
            context do
        html = render(context.fresh_vassal_live)

        [started_turn] =
          Regex.run(~r/data-test="rebellion-started-turn"[^>]*>(\d+)</, html,
            capture: :all_but_first
          )

        assert started_turn == context.turn_before,
               "the Rebellion's own recorded start turn should match the turn number at declare time"

        [army_size] =
          Regex.run(~r/data-test="rebellion-army-size"[^>]*>(\d+)</, html, capture: :all_but_first)

        assert String.to_integer(army_size) >= 0

        [risen_count] =
          Regex.run(~r/data-test="rebellion-risen-cities"[^>]*>(\d+)</, html,
            capture: :all_but_first
          )

        [contested_count] =
          Regex.run(~r/data-test="rebellion-contested-cities"[^>]*>(\d+)</, html,
            capture: :all_but_first
          )

        assert String.to_integer(risen_count) + String.to_integer(contested_count) == 1,
               "Wes's one occupied city should be accounted for as either risen or still contested"

        {:ok, context}
      end
    end
  end
end
