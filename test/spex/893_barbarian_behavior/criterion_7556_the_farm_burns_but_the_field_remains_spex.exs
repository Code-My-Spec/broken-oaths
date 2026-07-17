defmodule BrokenOathsSpex.Story893.Criterion7556Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7556 — a barbarian entering a completed improvement
  pillages it: the improvement is removed from the tile (per
  stone_age.md §3.2, "removed from the map"), yields stop, and a
  worker can repair it, which takes exactly 1 turn — much less than a
  fresh build (Farm: 3 turns, per `Improvement.duration/1`).

  Barbarian-fixture note: see criterion 7551's moduledoc — this uses a
  REAL camp-spawned warrior, one of the 1-2 camps that spawn already
  inside the player's own territory (criterion 7543).

  Setup-hardening history (why this file no longer marches anything
  through a live world, and no longer relies on AI path-finding to get
  the barbarian onto `farm_tile` at all): the worker and the lord used
  to WALK to their spots via `queue_move` + turn-boundary wait loops,
  and the barbarian's arrival on `farm_tile` used to be produced by
  really letting `Turn`'s AI hunt a deliberately-placed lord across a
  "bridge" tile (the same technique criterion 7536, story 891, uses to
  land a unit on a specific intermediate hex — camp -> farm tile ->
  mid tile -> lord, forcing the first hop onto the farmed tile). Two
  DISTINCT, genuine same-tick-timing hazards showed up under repeated
  runs, not rare edge cases:

    1. A worker standing on `farm_tile` (a direct camp neighbor, by
       construction) for the three real turns a Farm takes to dig is
       exposed to this SAME camp's own spawn cadence: `resolve_camp_spawns`
       runs earlier in `Turn.tick/1` than `resolve_barbarian_ai`, so a
       brand-new warrior can be born already adjacent and strike
       within that very same tick — no pre-tick vicinity check can see
       it coming. Fixed by placing the finished farm directly via
       `Fixtures.complete_improvement/3` instead — no worker ever
       needs to stand there to begin with.

    2. Even with the farm placed directly, relying on `Turn`'s live,
       multi-camp AI tick to walk this criterion's OWN barbarian onto
       `farm_tile` (via the bridge technique) was hostage to every
       OTHER camp's own independent, same-tick spawn/movement cadence:
       an unrelated warrior could land on the exact bridge tile this
       scenario needed clear at the exact moment its own decision was
       computed, no PRE-tick clearing (however thorough) can rule that
       out, and hex-grid ties between the "bridge" tile and a sibling
       camp neighbor (equally close to a naively-chosen lord target)
       made this a routine, not rare, failure. Fixed by recognizing
       this criterion's actual SUBJECT is pillage-ON-ENTRY, not the
       AI's own path-finding to get there (already covered by criteria
       7551/7554): `Fixtures.move_barbarian/3` moves the barbarian
       directly onto `farm_tile`, applying the same pillage-on-entry
       rule `Turn` itself would, as one isolated write instead of a
       full multi-camp tick.

  Re-anchored (every other actor eliminated, not tolerated): the
  previous version above still let the LATER "worker returns to
  repair" phase run through several real `advance_turn` boundaries in
  a live, multi-camp world — a documented "1-in-20" residual measured
  independently at closer to 1-in-5. This world always ships with
  several OTHER, independently-roaming real camps besides the one this
  criterion tracks (criterion 7543), and `resolve_camp_spawns` runs
  before `resolve_barbarian_ai` every tick, so a brand-new warrior born
  THAT SAME tick can still end up adjacent to `farm_tile` and strike —
  no pre-tick check can rule out a spawn that doesn't exist yet. Fixed
  by eliminating the other actors outright instead of tolerating them:

    * `Fixtures.isolate_camp/2` destroys every OTHER camp and
      hard-deletes their warriors the moment the tracked camp is known
      — before city1/the worker/the lord are even placed — so no other
      camp exists to interfere for the rest of this scenario.
    * `Fixtures.clear_camp_warriors/2` removes any sibling THIS SAME
      (tracked, never-isolated) camp's own natural cadence accumulated
      during the 12-turn production wait, right before this
      criterion's own deliberate warrior is placed.
    * "The barbarian moves on" is now a direct `Fixtures.relocate_unit/3`
      back to `camp_tile`, not a real multi-turn wait for the AI to
      wander off on its own — that wandering is criteria 7551/7554's
      subject, not this one's.
    * Immediately before the decisive repair tick, `Fixtures.isolate_camp/2`
      is called again with a sentinel matching no real camp id,
      destroying EVERY camp including the tracked one — nothing after
      the repair assertion needs any barbarian alive, so
      `resolve_barbarian_ai` has nothing left to iterate over that
      could kill the worker or re-pillage the tile mid-tick.

  Both decisive boundaries (the pillage-on-entry write, and the
  one-turn repair tick) now run with either zero or exactly one
  barbarian actor in the entire world — a faithful "one clean tick"
  test of each SUBJECT, not a race against a living system.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the farm burns but the field remains" do
    scenario "a barbarian pillages a farm it walks through, and a worker repairs it in one turn" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, revealing a nearby barbarian camp",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [camp | _] = camps0
        [city] = Fixtures.player_cities(context.world, context.user)

        # Eliminate every OTHER camp right away, before any wait even
        # starts — see this module's doc: this criterion's SUBJECT is
        # ONE camp's own pillage-on-entry/repair-timing behavior, not
        # whether it survives incidental interference from the several
        # OTHER camps this world always ships with (criterion 7543).
        :ok = Fixtures.isolate_camp(context.world, camp.id)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)}
      end

      given_ "a completed farm sits on the barbarian's only path to a distant lord", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        farmable? = fn t ->
          terrain = Fixtures.tile_terrain(context.world, t)
          terrain.relief == :flat and terrain.feature == nil and terrain.base in [:grassland, :plains]
        end

        camp_neighbors = Fixtures.adjacent_tiles(context.world, context.camp_tile) |> Enum.filter(land?)
        farm_tile = Enum.find(camp_neighbors, farmable?)

        # `lord_target` no longer has to be the UNIQUE shortest route
        # from `camp_tile` — the barbarian is placed directly onto
        # `farm_tile` below (`Fixtures.move_barbarian/3`), not walked
        # there by AI path-finding, so there's nothing left for a tied
        # alternate route to hijack. This only needs to land somewhere
        # far enough (within the barbarian's own aggro/leash range once
        # it's standing ON `farm_tile`) to give the LATER "worker
        # returns to repair" phase's real `advance_turn` loop something
        # to lure it away with.
        mid_tile =
          Fixtures.adjacent_tiles(context.world, farm_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.camp_tile))
          |> Enum.reject(&(&1 in camp_neighbors))
          |> List.first()

        lord_target =
          Fixtures.adjacent_tiles(context.world, mid_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == farm_tile))
          |> Enum.reject(&(&1 == context.camp_tile))
          |> Enum.reject(&(&1 in camp_neighbors))
          |> List.first()

        # Produce a worker — still needed for real later, to repair the
        # farm after it's pillaged — but the farm itself is placed
        # directly (`Fixtures.complete_improvement/3`) rather than built
        # by standing a worker on `farm_tile` for the three real turns a
        # Farm takes to dig. `farm_tile` is a direct camp neighbor by
        # construction (the whole point of the "bridge" — see this
        # module's doc), so a worker planted there for three real,
        # exposed turns is at genuine risk from this SAME camp's own
        # natural spawn cadence: `resolve_camp_spawns` runs earlier in
        # `Turn.tick/1` than `resolve_barbarian_ai`, so a brand-new
        # warrior can be born already adjacent to the worker and strike
        # within that very same tick — no vicinity check made before
        # that tick even started could have seen it coming. That
        # exposure risk belongs to story 893's own AI-vs-worker
        # criteria, not to getting a finished farm to exist for THIS
        # criterion's actual subject (pillage-then-repair, criterion
        # 7556 itself).
        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "worker"
        })

        # `queue_production` broadcasts `:cities_changed`, which also
        # triggers a "game:camps" push — drain it too, same reasoning
        # as the loop below.
        assert_push_event(context.play_live, "game:camps", %{camps: _}, 500)

        # Each `advance_turn` broadcasts a fresh "game:camps" push to
        # `play_live` — `assert_push_event` always matches the FIRST
        # matching message still sitting in the mailbox, so leaving
        # eleven of these twelve undrained would make the later
        # `when_` block's own `assert_push_event` see turn 1's camp
        # state (before this scenario's own barbarian even exists)
        # instead of the fresh state its own `advance_turn` produced.
        for _ <- 1..12 do
          Fixtures.advance_turn(context.world)
          assert_push_event(context.play_live, "game:camps", %{camps: _}, 500)
        end

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        _farm = Fixtures.complete_improvement(context.world, farm_tile, :farm)

        assert Fixtures.tile_improvement(context.world, farm_tile) == :farm

        # Keep the worker garrisoned on the city's OWN tile rather than
        # parking it somewhere incidental (the farm itself never had a
        # worker standing on it in this rewrite — `complete_improvement/3`
        # placed it directly — so there's nothing to move the worker
        # AWAY from). `BarbarianAI.decide/5` unconditionally prefers an
        # undefended city over any unit in range (criterion 7554) —
        # once the lord below relocates away to its distant post, an
        # undefended city here would outrank the lord as this
        # criterion's own barbarian's target and break the "bridge"
        # geometry entirely. A DEFENDED city is never a target
        # candidate at all, so garrisoning the worker here keeps the
        # lord the sole distant target regardless of relative range.
        clear_tile(context.world, context.city.tile_id)
        :ok = Fixtures.relocate_unit(context.world, worker.id, context.city.tile_id)

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

        # Now place the lord at its 3-hexes-out post.
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        clear_tile(context.world, lord_target)
        :ok = Fixtures.relocate_unit(context.world, lord.id, lord_target)
        [lord] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        {:ok,
         context
         |> Map.put(:worker, worker)
         |> Map.put(:farm_tile, farm_tile)
         |> Map.put(:mid_tile, mid_tile)
         |> Map.put(:lord, lord)}
      end

      given_ "a barbarian warrior stands at the camp", context do
        # This SAME (tracked, never-isolated) camp's own natural spawn
        # cadence has had 12 real turns to accumulate a sibling warrior
        # before this deliberate placement — `Fixtures.clear_camp_warriors/2`
        # guarantees zero pre-existing warriors anywhere in the world at
        # this point (every OTHER camp was already eliminated above),
        # so spawning directly on `camp_tile` needs no occupancy check
        # anymore. Still a REAL, camp-tied warrior (`Turn`'s barbarian
        # AI loop drives it for real from the very next `advance_turn`
        # — see criterion 7551's moduledoc), needed for the pillage
        # step right below.
        Fixtures.clear_camp_warriors(context.world, context.camp_id)
        warrior = Fixtures.spawn_barbarian(context.world, context.camp_tile, context.camp_id)
        {:ok, Map.put(context, :barbarian, warrior)}
      end

      when_ "one more turn boundary passes and the barbarian steps onto the farm", context do
        # Direct placement (`Fixtures.move_barbarian/3`), not an AI-driven
        # `advance_turn` — see this module's doc: this criterion's
        # SUBJECT is pillage-on-entry, not path-finding, and driving
        # this arrival through a real multi-camp tick was hostage to
        # every OTHER camp's own same-tick spawn/movement cadence. A
        # real, unrelated warrior could still have wandered onto
        # `farm_tile` during the many production-wait turns earlier
        # (nothing cleared it since the geometry was first computed),
        # so clear it first.
        clear_tile(context.world, context.farm_tile)
        :ok = Fixtures.move_barbarian(context.world, context.barbarian.id, context.farm_tile)

        barbarian_after =
          context.world
          |> Fixtures.list_camps()
          |> Enum.find(&(&1.id == context.camp_id))
          |> Map.fetch!(:warriors)
          |> Enum.find(&(&1.id == context.barbarian.id))

        {:ok, Map.put(context, :barbarian_after, barbarian_after)}
      end

      then_ "the farm is pillaged, but the tile itself remains ordinary land", context do
        assert context.barbarian_after != nil
        assert context.barbarian_after.tile_id == context.farm_tile

        refute Fixtures.tile_improvement(context.world, context.farm_tile) == :farm
        assert Fixtures.tile_class(context.world, context.farm_tile) == :land
        {:ok, context}
      end

      when_ "the barbarian moves on and a worker returns to repair the farm", context do
        # Direct relocation, not a real multi-turn wait for the AI to
        # wander off on its own — see this module's doc: "the barbarian
        # moves on" is pure setup for the repair-timing assertion below,
        # not itself the thing being tested (pillage-on-entry, already
        # proven above; the AI's own targeting/roaming is criteria
        # 7551/7554's job). Send it back to its own camp tile, off
        # `farm_tile`, so the worker has somewhere to stand.
        :ok = Fixtures.relocate_unit(context.world, context.barbarian.id, context.camp_tile)
        :ok = Fixtures.relocate_unit(context.world, context.worker.id, context.farm_tile)

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.worker.id)})

        # Called directly (not via `render_hook`) so a validation
        # failure here surfaces as a MatchError right at the source
        # instead of a confusing "tile_improvement is nil" assertion
        # several lines later.
        :ok = BrokenOaths.Game.start_improvement(context.world, context.user, context.worker.id, :farm)

        # One clean tick for the decisive assertion: nothing after this
        # point needs any barbarian (this camp's or otherwise) to exist
        # — `Fixtures.isolate_camp/2` with a sentinel that matches no
        # real camp id destroys EVERY camp, including the tracked one,
        # so `resolve_barbarian_ai` has nothing left to iterate over
        # that could kill the worker or re-pillage the tile mid-tick.
        :ok = Fixtures.isolate_camp(context.world, :none)

        Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "a single turn's repair makes the farm whole again", context do
        assert Fixtures.tile_improvement(context.world, context.farm_tile) == :farm
        {:ok, context}
      end
    end
  end

  # This scenario's setup spends many real turns (production, waiting
  # for a pillager to move on) with a live, roaming camp active nearby,
  # so a real barbarian occasionally wanders onto a tile this criterion
  # needs to place something ELSE on exactly (the camp's own tile, the
  # lord's post, a parking spot, the farm tile before repair). Since
  # every such occupant here is always a real, camp-driven barbarian —
  # never one of the player's own units, which this criterion places
  # itself and tracks by id — relocating it out of the way (to any
  # other clear land tile adjacent to the one being cleared) is always
  # safe: it's still a real, AI-controlled warrior afterward, just not
  # standing exactly where this scenario needs to make room. A no-op
  # if `tile_id` is already clear.
  defp clear_tile(world, tile_id) do
    occupant =
      world
      |> Fixtures.list_camps()
      |> Enum.flat_map(& &1.warriors)
      |> Enum.find(&(&1.tile_id == tile_id))

    if occupant do
      parking =
        Fixtures.adjacent_tiles(world, tile_id)
        |> Enum.filter(&(Fixtures.tile_class(world, &1) == :land and &1 != tile_id))

      Enum.find_value(parking, fn t -> Fixtures.relocate_unit(world, occupant.id, t) == :ok end)
    end

    :ok
  end
end
