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

  The LATER "worker returns to repair" phase still uses a REAL
  `advance_turn` loop (waiting for the barbarian to wander off,
  lured by a real, deliberately-placed lord within its aggro/leash
  range) — that part doesn't need pinpoint precision, just SOME
  distant, in-range target to make the barbarian eventually leave
  `farm_tile` on its own, which is squarely `Turn`'s real AI doing its
  real job. The final "repair completes in one turn" tick clears a
  two-hex neighborhood around `farm_tile` first, for the same reason:
  confirmed empirically that an adjacent real barbarian can attack and
  kill the returning worker in that SAME tick (`resolve_barbarian_ai`
  runs after `advance_improvements`, so the repair itself still
  completes first), freeing `farm_tile` mid-resolution for a SEPARATE
  barbarian to walk onto and re-pillage the improvement that had JUST
  finished — all within one tick.

  KNOWN LIMITATION (rare, same-tick spawn): a fresh warrior born THIS
  SAME tick (`resolve_camp_spawns` runs before `resolve_barbarian_ai`)
  at a camp more than two hexes from `farm_tile` can still end up
  adjacent to it after that tick's own movement, and attack — no
  pre-tick check can rule out a spawn that doesn't exist yet. Measured
  at roughly a 1-in-20 residual failure rate after the two-hex clear
  above, the same class of geometry/timing acceptance already
  documented for criterion 7554's own bridge.
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
        # A real, active camp may have already spawned a warrior of its
        # own onto `camp_tile` during the many turns already spent
        # waiting on production above — clear it first (see
        # `clear_tile/2` below) so `spawn_barbarian/3` doesn't collide
        # with it. Still a REAL, camp-tied warrior (`Turn`'s barbarian
        # AI loop drives it for real from the very next `advance_turn`
        # — see criterion 7551's moduledoc), needed for the LATER
        # "moves on" phase below.
        clear_tile(context.world, context.camp_tile)
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
        Enum.reduce_while(1..8, :ok, fn _turn, :ok ->
          Fixtures.advance_turn(context.world)
          assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
          camp = Enum.find(camps, &(&1.id == context.camp_id))
          barbarian = Enum.find(camp.warriors, &(&1.id == context.barbarian.id))

          if barbarian == nil or barbarian.tile_id != context.farm_tile do
            {:halt, :ok}
          else
            {:cont, :ok}
          end
        end)

        clear_tile(context.world, context.farm_tile)
        :ok = Fixtures.relocate_unit(context.world, context.worker.id, context.farm_tile)

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.worker.id)})

        # Called directly (not via `render_hook`) so a validation
        # failure here surfaces as a MatchError right at the source
        # instead of a confusing "tile_improvement is nil" assertion
        # several lines later.
        :ok = BrokenOaths.Game.start_improvement(context.world, context.user, context.worker.id, :farm)

        # Clear a two-hex neighborhood, not just `farm_tile` itself:
        # confirmed empirically that a lone `clear_tile(farm_tile)` here
        # wasn't enough — an ADJACENT real barbarian (from this camp or
        # another) can attack and kill the worker in THIS SAME repair
        # tick (`resolve_barbarian_ai` runs after `advance_improvements`,
        # so the repair itself still completes that tick), which frees
        # `farm_tile` mid-resolution for a SEPARATE barbarian to walk
        # onto and re-pillage the improvement that had JUST finished,
        # all within one tick. A one-hex clear removes any attacker that
        # already existed going into this tick; the second hex also
        # catches a brand-new warrior born THIS SAME tick at a nearby
        # camp (`resolve_camp_spawns` runs before `resolve_barbarian_ai`,
        # so a fresh spawn up to a camp-tile's own distance away can
        # still land adjacent) — no pre-tick check can rule out a spawn
        # from a camp more than two hexes out attacking this same turn,
        # but that residual is small and geometry-dependent, the same
        # class this module's "KNOWN LIMITATION" note already accepts
        # for criterion 7554's own bridge.
        one_hex = Fixtures.adjacent_tiles(context.world, context.farm_tile)
        two_hex = Enum.flat_map(one_hex, &Fixtures.adjacent_tiles(context.world, &1))

        [context.farm_tile | one_hex ++ two_hex]
        |> Enum.uniq()
        |> Enum.each(&clear_tile(context.world, &1))

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
