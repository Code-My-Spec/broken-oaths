defmodule BrokenOathsSpex.Story917.Criterion7746Spex do
  @moduledoc """
  Story 917 — Lord's Death — Seize the Moment
  Criterion 7746 — "A realm whose Lord unit has fallen has no lord
  present to answer a Protection Pact or retaliate, so a rising vassal
  faces no lordly counterattack unless and until the lordship is
  re-established. Breaking away from a leaderless realm is simply
  easier — by absence, not by any bonus."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story 917).

  ## Known limitation — Protection Pact (914) isn't built either

  `grep -rn protection_pact lib/` comes back empty — story 914
  (Protection Pact) isn't listed as one of THIS story's own
  dependencies ("combat/Lord unit, Vassalage (907), Rebellion
  (915/919)") and hasn't shipped. The "no Protection Pact response is
  raised" clause is therefore currently VACUOUSLY true regardless of
  whether the lord is alive or dead — there is no Protection Pact
  response mechanism anywhere yet for either case. This spec still
  encodes the assertion faithfully (refuting any
  `data-test="protection-pact"`-shaped element), but flags that it
  cannot meaningfully discriminate "leaderless" from "led" until 914
  ships; the assertion that DOES carry real signal today is the
  "no lordly counterattack" clause below, which this spec makes the
  anchor of its own `then_`.

  ## "No lordly counterattack marches on the risen cities" — the real,
  falsifiable assertion

  This spec reads the risen city's own `city-hp`/`city-status` (via
  `Fixtures.player_cities/2`, the same sanctioned board-state read
  `criterion_7679`'s own `then_` already relies on) both right after
  the declaration and again after many real turn boundaries pass with
  no player-driven action against it, and asserts the city stays at
  full HP and un-reoccupied throughout — the literal, falsifiable
  content of "no counterattack marches."

  ## Scope boundary: no live-lord differential control run

  "The ease of breaking away comes purely from the lord's absence,
  with no buff applied" could in principle be proven by comparing this
  scenario's outcome against an identical-strain vassal declaring
  against a STILL-LIVING lord and asserting equal results. That
  comparison was judged out of scope for a single criterion spec here:
  the exact army-size/city-rise formulas it would need to hold equal
  are story 915's own component to own (see `criterion_7745`'s own
  moduledoc), and duplicating a full second lord/vassal/siege setup
  just to diff two not-yet-built formulas risks the spec asserting
  915's contract rather than 917's. Instead this spec proves the
  narrower, still-faithful claim directly stated in the rule text: NO
  counterattack happens and NO special buffed/protected state is
  shown — "purely from absence" is satisfied by the absence of any
  such affordance, not by a side-by-side numeric comparison.

  ## Not-yet-built surface

  Same `declare_independence` seam as `criterion_7744`/`criterion_7745`
  — driven through `attempt_event/3`.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a leaderless realm cannot answer or retaliate", fail_on_error_logs: false do
    scenario "a vassal who rises against a fallen, unreplaced lord faces no Protection Pact response or counterattack" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a vassal whose lord's Lord unit has fallen and has not been replaced", context do
        context = a_freshly_subjugated_vassal(context)

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.my_lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.my_lord.tile_id))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)
        Fixtures.set_unit_hp(context.world, context.my_lord.id, 1)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, context.my_lord.id)

        {:ok, context}
      end

      given_ "the vassal declares independence against the now-leaderless lord", context do
        attempt_event(context.other_play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        [city_just_after] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        {:ok, Map.put(context, :city_just_after, city_just_after)}
      end

      when_ "the rebellion resolves over the following turns", context do
        for _ <- 1..30, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "no lordly counterattack marches on the risen cities", context do
        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        assert city_now.hp == context.city_just_after.hp,
               "the risen city's HP moved from #{context.city_just_after.hp} to #{city_now.hp} over 30 quiet turns — nothing should be able to besiege it while the realm is leaderless"

        assert Map.get(city_now, :status, :free) != :occupied,
               "the risen city should never fall back to occupied without a live lord to march on it"

        {:ok, context}
      end

      then_ "no Protection Pact response is raised on the vassal's behalf, and the ease comes purely from absence, not a bonus",
            context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        # Anchor: the page rendered real content for this player (proves
        # the refute below isn't vacuously true from an empty page).
        assert has_element?(fresh_vassal_live, "[data-test='player-gold']")

        refute has_element?(fresh_vassal_live, "[data-test='protection-pact']"),
               "no Protection Pact affordance should exist for a vassal with no lord present to answer one"

        refute has_element?(fresh_vassal_live, "[data-test='vassal-status']"),
               "the vassal should read as free, not as still sworn under some special leaderless-window buff state"

        {:ok, context}
      end
    end
  end
end
