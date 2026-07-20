defmodule BrokenOathsSpex.Story895.Criterion7568Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7568 — a city reduced to 0 HP by a BARBARIAN is pillaged,
  not captured: it loses one population, its production queue freezes
  for three turn boundaries, and its HP resets to 50 (not 0). The
  frozen production resumes on the fourth boundary from wherever it
  was banked — it does not restart from zero.

  Rewritten for the v0.2.1 playtest issue 11500df6 ("story 906 Siege
  changes the shared attack-a-city surface, breaking 895's pillage
  spex"): the original version drove a SECOND REAL REGISTERED PLAYER's
  own warrior over the immediate `"attack"`/`target_city_id` surface
  as a barbarian stand-in — the same convention story 906's own
  criterion 7652 moduledoc names. Story 906 (`BrokenOaths.Game.Siege`)
  now makes THAT surface break a city (capture path) instead of
  pillaging it, which is correct for a real player attack but wrong
  for what this criterion actually means to test. Genuine pillage still
  happens exactly as before — it's resolved by `BrokenOaths.Game.
  CityDefense.take_damage/3` inside `Turn.tick`'s own barbarian-AI
  phase (`resolve_barbarian_city_attack/3`), a code path story 906
  never touched. This version drives a REAL, camp-tied barbarian
  warrior over THAT path instead, via `Fixtures.spawn_barbarian/3` +
  `Fixtures.advance_turn/1` — no second player needed at all.

  Reach note: `BrokenOaths.Game.BarbarianAI`'s own leash (5 hexes from
  the warrior's OWN camp) means a camp from THIS city's own founding
  (always 8-15 hexes out, story 892) can never reach the founding city
  itself — the same reach constraint criterion 7554 (story 893) already
  works around. This spec follows that same precedent: found a first
  city normally (to learn one of its camps and to safely produce a
  settler far from it), then found a SECOND city within a few hexes of
  that camp — the one actually placed under test — and drive the
  barbarian against IT.

  Grows the second city to size 2 first (the `City` changeset floors
  `size` at 1 — `lib/broken_oaths/cities/city.ex` — so "-1 population"
  needs a size-2 starting point to land on an unambiguous, schema-legal
  size 1 afterward). No garrison: an undefended city means every attack
  damages the city and NONE bounces back onto the barbarian
  (`CityDefense.resolve_attack/4` returns `damage_to_barbarian: 0` with
  no defender), keeping the attacker alive across the whole softening
  loop with no extra bookkeeping needed.

  A Worker (cost 60, no "second citizen to spare" gating unlike
  Settler — see `GameLive.CityPanel.catalog_option/1`) is queued
  five times over as the in-flight production, after un-working the
  city's own auto-assigned tile (see criterion 7562's own moduledoc for
  the same fix), so there is real banked progress for the pillage to
  freeze and later resume, however many boundaries the softening loop
  needs. The exact number of hits needed to reach 0 HP isn't knowable
  ahead of time, so the softening loop is bounded generously (25
  attacks) rather than counted precisely — a documented uncertainty,
  not a fabricated number.

  Camp isolation: every OTHER camp is destroyed the moment the tracked
  one is known (`Fixtures.isolate_camp/2`), and the tracked camp's OWN
  natural spawns are swept away before every single turn boundary from
  the moment the second city is founded onward
  (`Fixtures.clear_camp_warriors/2`, called every tick alongside
  `advance_turn/1` — a spawned-this-tick warrior never acts before the
  FOLLOWING boundary per `Turn.resolve_barbarian_ai/3`'s own doc, so
  clearing at the START of every tick catches it before it ever
  decides) — the whole point is ONE deterministically-placed, tracked
  barbarian doing 100% of the damage this criterion observes, not
  whichever natural warrior happens to wander over first during the
  city's own real-turn growth window.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "sacked but still mine" do
    scenario "repeated real-barbarian attacks pillage the city instead of capturing it" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, revealing a barbarian camp, with every other camp eliminated",
             context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [camp | _] = camps0
        [city1] = Fixtures.player_cities(context.world, context.user)

        :ok = Fixtures.isolate_camp(context.world, camp.id)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city1, city1)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)}
      end

      given_ "a second, undefended city is founded within the tracked camp's reach", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        ring2 =
          Enum.reduce(1..2, {[context.camp_tile], MapSet.new([context.camp_tile])}, fn
            _, {frontier, seen} ->
              next =
                frontier
                |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
                |> Enum.uniq()
                |> Enum.filter(land?)
                |> Enum.reject(&MapSet.member?(seen, &1))

              {next, MapSet.union(seen, MapSet.new(next))}
          end)
          |> elem(0)

        [city_target | _] = Enum.sort(ring2)

        # Grow city1 to size 2 (settlers need size >= 2) and bank a
        # settler — city1 sits 8-15 hexes from EVERY camp its own
        # founding placed (story 892), always outside a barbarian's
        # 5-hex leash, so this whole phase is naturally safe without
        # any clearing.
        Enum.reduce_while(1..80, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == context.city1.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            drain_events(context.play_live, "game:camps")
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city1.id),
          "item" => "settler"
        })

        drain_events(context.play_live, "game:camps")

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          case for(u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u) do
            [_ | _] ->
              {:halt, :ok}

            [] ->
              Fixtures.advance_turn(context.world)
              drain_events(context.play_live, "game:camps")
              {:cont, :ok}
          end
        end)

        [new_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        # From here on the settler (then the city it founds) sits
        # within the tracked camp's own reach — sweep its natural
        # spawns before every boundary from now on (see moduledoc).
        :ok = relocate_when_free(context.world, context.camp_id, context.play_live, new_settler.id, city_target)
        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(new_settler.id)})
        drain_events(context.play_live, "game:camps")

        [city2] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id != context.city1.id,
            do: c

        assert city2.tile_id == city_target
        assert Enum.all?(Fixtures.player_units(context.world, context.user), &(&1.tile_id != city2.tile_id))

        {:ok, Map.put(context, :city2, city2)}
      end

      given_ "the second city grows to size 2, banks real production, and a barbarian stands ready to attack it",
             context do
        # Grow to size 2 with whatever tile the founding pop auto-
        # worked (we WANT growth here); only after reaching size 2 does
        # slowing accrual for the production-banking phase matter (see
        # criterion 7562's own moduledoc for the same "un-work after
        # growth" sequencing).
        Enum.reduce_while(1..150, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city2.id,
              do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.clear_camp_warriors(context.world, context.camp_id)
            Fixtures.advance_turn(context.world)
            drain_events(context.play_live, "game:camps")
            {:cont, :ok}
          end
        end)

        [city2] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city2.id, do: c

        # See original moduledoc's un-work rationale: dropping accrual
        # to the flat base alone guarantees a "Worker" item is still in
        # progress whenever pillage lands, however many boundaries the
        # softening loop below needs (capped at 25). Unlike criterion
        # 7562's own precedent (a size-1 city, exactly one auto-worked
        # tile), a size-2 city auto-works TWO (story 880, "each citizen
        # works one tile beyond the free center") — un-working only the
        # first still leaves the second feeding growth. Also unlike
        # 7562, this criterion needs more than "no further growth": a
        # barbarian pillage does NOT reset `food` (only `size`/`hp`/
        # `worked_tiles`/`production_halted_until` — see `CityDefense.
        # pillage/2`), so any food ALREADY banked past the size-1
        # threshold (20, ten below size 2's own 30) before the pillage
        # strikes would re-cross it and instantly regrow the city right
        # back on the very same or next boundary — masking the
        # population loss this criterion means to observe (measured:
        # it does, intermittently). Un-working EVERY worked tile drops
        # accrual to the unavoidable flat center minimum (2/turn),
        # keeping banked food low enough, long enough, for the
        # softening loop below to reliably observe the drop before it
        # can be undone.
        for worked <- city2.worked_tiles do
          render_hook(context.play_live, "assign_worked_tile", %{
            "city_id" => to_string(city2.id),
            "from_tile_id" => to_string(worked)
          })
        end

        for _ <- 1..5 do
          render_hook(context.play_live, "queue_production", %{
            "city_id" => to_string(city2.id),
            "item" => "worker"
          })
        end

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(city2.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(fn t ->
            Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.tile_id == t))
          end)

        Fixtures.clear_camp_warriors(context.world, context.camp_id)
        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target, context.camp_id)

        {:ok,
         context
         |> Map.put(:city2, city2)
         |> Map.put(:city_size0, city2.size)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "repeated real barbarian attacks whittle the city down to 0 HP", context do
        # Read the authoritative `Fixtures.player_cities/2` city map
        # directly (`hp`/`queue` — a REAL WorldServer read) rather than
        # scraping `play_live`'s own rendered HTML: the LiveView only
        # refreshes its cached assigns once it's processed the PubSub
        # broadcast `advance_turn/1` fires, an async hop with no
        # ordering guarantee relative to a same-tick `render_hook`/
        # `render` call from this (different) test process — a real,
        # measured source of flakiness this rewrite avoids entirely by
        # never depending on it for the loop's own halt condition.
        #
        # `discard_other_camp_warriors/2` (below) is called every
        # single iteration, BEFORE `advance_turn`: the tracked camp's
        # own natural 3-turn cadence keeps running the whole time (it
        # was only ever swept during the earlier growth phase, not
        # here), so a SECOND, untracked warrior spawning mid-loop and
        # ALSO landing on the same undefended city — in the SAME tick
        # as the tracked one, since `Turn`'s barbarian-AI phase resolves
        # every camp-tied warrior that same boundary — would land a
        # second, uncounted hit AFTER the first one's pillage-reset,
        # corrupting the exact "resets to 50" reading below (measured:
        # it does, intermittently — HP observed at 26 and 34 instead of
        # 50 before this guard). Keeping only the ONE deliberately
        # tracked barbarian alive is the whole point of this criterion's
        # own controlled setup.
        city_after =
          Enum.reduce_while(1..25, :ok, fn _, :ok ->
            discard_other_camp_warriors(context.world, context.camp_id, context.barbarian.id)
            Fixtures.advance_turn(context.world)

            [c] =
              for cc <- Fixtures.player_cities(context.world, context.user),
                  cc.id == context.city2.id,
                  do: cc

            if c.size < context.city_size0, do: {:halt, c}, else: {:cont, :ok}
          end)

        # The observation turns below (production freeze/resume) must
        # never see a SECOND pillage muddy the "no progress for exactly
        # three boundaries" window. Relocating the barbarian isn't
        # enough — its own camp sits only 2 hexes from this same city
        # (a structural requirement of reaching it at all, see this
        # file's own moduledoc "Reach note"), well within the camp's
        # own `@roam_radius` (2), so it would simply wander back within
        # striking range on its own over the next couple of boundaries
        # (measured: it does). It has already done its one job —
        # retire it outright.
        :ok = Fixtures.remove_unit(context.world, context.barbarian.id)

        {:ok,
         context
         |> Map.put(:city_after, city_after)
         |> Map.put(:banked_at_pillage, banked_of(city_after))}
      end

      then_ "the city loses one population", context do
        assert context.city_after.size == context.city_size0 - 1
        {:ok, context}
      end

      then_ "the city's HP resets to 50, not 0", context do
        assert context.city_after.hp == 50
        {:ok, context}
      end

      # `CityDefense.production_halted?/2`'s own doc: "a city pillaged at
      # turn T freezes accrual for exactly the three boundaries that
      # bump the turn from T→T+1, T+1→T+2, and T+2→T+3" — T→T+1 is the
      # VERY TICK that pillages. `Turn.tick/1`'s own pipeline runs
      # `accrue_production/1` BEFORE the barbarian-AI phase that
      # actually calls `CityDefense.take_damage/3`, so for a REAL
      # barbarian (unlike the old immediate pre-tick "attack" surface
      # this spex used to drive), that first frozen boundary's own
      # accrual already ran, un-frozen, moments before the freeze was
      # even set — `banked_at_pillage` (captured right after that same
      # tick) already reflects it. Two MORE boundaries stay visibly
      # frozen after that; the third resumes.
      then_ "production makes no progress for the next two turn boundaries", context do
        for _ <- 1..2, do: Fixtures.advance_turn(context.world)

        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city2.id, do: c

        assert banked_of(city) == context.banked_at_pillage
        {:ok, context}
      end

      then_ "the third boundary after that resumes production from the banked progress, not from zero",
            context do
        Fixtures.advance_turn(context.world)

        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city2.id, do: c

        assert banked_of(city) > context.banked_at_pillage

        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city2.id)})
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Worker")
        {:ok, context}
      end
    end
  end

  # Hard-deletes every warrior tied to `camp_id` EXCEPT `keep_id` —
  # `Fixtures.clear_camp_warriors/2` is all-or-nothing (it would delete
  # the one warrior this criterion is deliberately tracking too), so
  # this walks `Fixtures.list_camps/1`'s own ground truth instead and
  # removes just the extras, one `Fixtures.remove_unit/2` at a time.
  defp discard_other_camp_warriors(world, camp_id, keep_id) do
    camp = world |> Fixtures.list_camps() |> Enum.find(&(&1.id == camp_id))

    for w <- camp.warriors, w.id != keep_id, do: Fixtures.remove_unit(world, w.id)

    :ok
  end

  # `Fixtures.relocate_unit/3`, retried across a few turn boundaries if
  # the target is momentarily held (same technique criterion 7554
  # already established), sweeping the tracked camp's own natural
  # spawns on every retry too — see this file's own moduledoc.
  defp relocate_when_free(world, camp_id, play_live, unit_id, tile_id, retries \\ 10)
  defp relocate_when_free(_world, _camp_id, _play_live, _unit_id, _tile_id, 0), do: {:error, :occupied}

  defp relocate_when_free(world, camp_id, play_live, unit_id, tile_id, retries) do
    case Fixtures.relocate_unit(world, unit_id, tile_id) do
      :ok ->
        :ok

      {:error, :occupied} ->
        Fixtures.clear_camp_warriors(world, camp_id)
        Fixtures.advance_turn(world)
        drain_events(play_live, "game:camps")
        relocate_when_free(world, camp_id, play_live, unit_id, tile_id, retries - 1)
    end
  end

  # `Fixtures.player_cities/2`'s own `queue` shape — a
  # `[%{id:, type:, banked:, cost:}]` list, head = current item (see
  # the Fixtures moduledoc) — never empty here, since this file's own
  # setup keeps five Workers queued throughout.
  defp banked_of(city) do
    [%{banked: banked} | _] = city.queue
    banked
  end
end
