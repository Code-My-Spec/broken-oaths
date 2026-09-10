defmodule BrokenOathsSpex.Story892.Criterion7545Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7545 — a barbarian camp that was unexplored becomes a
  distinct marker on the map the moment a player's unit brings its
  tile into sight. Truth surface is the "game:camps" push (mirroring
  "game:cities"/"game:units" — board doctrine: canvas paint is never
  asserted), inferred not-yet-implemented shape `%{id:, tile_id:,
  hp:, warriors: [...]}` (see the Fixtures moduledoc for
  `list_camps/1`).

  The far camp's tile is located via `Fixtures.list_camps/1` (a
  sanctioned ground-truth read, same status as `region_partition` —
  it has no UI surface until scouted) purely to plan the `given_`/
  `when_` (where to walk the lord). The outcome itself — the camp
  appearing on the board — is asserted only through the push event
  the real "queue a move into the fog, walk there across turns"
  surface produces, the same technique criterion 7441 (story 875)
  established for orders into unexplored terrain.

  `"game:camps"` is content-diffed against its last-pushed value (QA
  issue dbcbd478): a turn (or a `queue_move`, which executes
  immediately and broadcasts `:units_changed` on its own) only
  re-pushes when the camp SET itself actually changed, unlike
  "game:units"/"game:cities", which still push unconditionally on
  every board refresh. `latest_camps/2` (not `assert_push_event`)
  tracks the running snapshot turn-by-turn, falling back to the last
  KNOWN state whenever a given march step produces no push at all —
  the correct read now, since a quiet mailbox means the camp set
  genuinely didn't change that step.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a camp discovered is a camp marked" do
    scenario "marching the lord within sight of a wilderness camp reveals its marker" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, out of sight of a wilderness camp",
             context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: initial_camps})

        visible_ids = MapSet.new(initial_camps, & &1.tile_id)

        [target_camp | _] =
          context.world
          |> Fixtures.list_camps()
          |> Enum.reject(&MapSet.member?(visible_ids, &1.tile_id))

        # QA issue (flaky test, ~1-in-5 failure rate): founding spawns
        # SEVERAL camps at once (7, in the standard seed 424242/
        # frequency 8 world), not just `target_camp`. Left un-isolated,
        # every other camp is free to spawn and roam warriors of its
        # own across the up-to-60 real turns this scenario's own
        # `when_` marches through — same interference class story 895's
        # own criterion_7567/criterion_7566 already guard against with
        # `Fixtures.isolate_camp/2` (see `SharedGivens.
        # clear_all_camps/1`'s own doc), just never applied here.
        # `target_camp` itself is untouched by this call (still
        # undiscovered, still there to reveal) — `isolate_camp/2`
        # deliberately "leaves the KEPT camp's own warriors alone" per
        # its own doc, so this narrows the interference source down to
        # `target_camp`'s own warriors alone; the `when_` step's own
        # fix (below) is what closes that remaining gap.
        :ok = Fixtures.isolate_camp(context.world, target_camp.id)

        land_neighbor =
          context.world
          |> Fixtures.adjacent_tiles(target_camp.tile_id)
          |> Enum.find(&(Fixtures.tile_class(context.world, &1) == :land))

        [scout | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:target_camp, target_camp)
         |> Map.put(:land_neighbor, land_neighbor)
         |> Map.put(:scout, scout)
         |> Map.put(:camps, initial_camps)}
      end

      when_ "the lord marches to the camp's doorstep", context do
        {x, y, z} = Fixtures.tile_center(context.world, context.land_neighbor)

        # Raw integer, not a string: unlike "found_city", the
        # "queue_move" handler never runs `unit_id` through
        # `Play.parse_id/1`, so a stringified id reads as
        # `:not_owner` and the march never queues at all.
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.scout.id,
          "to_point" => [x, y, z]
        })

        # `queue_move` executes immediately and broadcasts
        # `:units_changed`, but a plain move never changes the camp
        # SET — content-diffed `push_camps/2` (QA issue dbcbd478)
        # produces no push here, so the running snapshot is still
        # `context.camps` unchanged.
        camps_before = latest_camps(context.play_live, context.camps)

        # QA issue (same flaky-test investigation as the `given_` step's
        # own `isolate_camp/2` comment): even with every OTHER camp
        # isolated away, `target_camp` was free to spawn its OWN
        # warrior mid-march — and that warrior didn't need to catch the
        # scout by roaming into it; the scout's own QUEUED PATH could
        # (and, once `target_camp` stopped varying run to run while
        # this was being debugged, reliably DID) pass directly through
        # a tile the freshly-spawned warrior now stood on, snarling the
        # march into repeated combat rather than a clean walk-past.
        # `Fixtures.player_units/2` no longer containing the scout's id
        # once that combat killed it crashed `scout_now` below with a
        # raw `MatchError` on `[]`, not a normal assertion failure —
        # the tell that something other than "the march is still in
        # progress" was going on.
        #
        # The actual fix: this loop was marching all the way to
        # `land_neighbor` even though the scenario's own subject —
        # `target_camp` turning up in the pushed camp set — is
        # typically satisfied several turns before the scout physically
        # arrives (vision reaches beyond the scout's own tile). Once
        # discovered, continuing to march the scout INTO the camp's own
        # backyard is pure unrewarded risk this scenario never needed
        # to take. Halting the instant `target_camp` appears in `camps`
        # (in addition to the existing "order complete" halt) answers
        # the scenario's own question as soon as it's answered, instead
        # of gambling on a clean arrival too.
        scout_now = fn ->
          case for u <- Fixtures.player_units(context.world, context.user),
                   u.id == context.scout.id,
                   do: u do
            [u] -> u
            [] -> flunk("the scouting lord died before reaching #{context.target_camp.tile_id}")
          end
        end

        {_final_unit, camps_after} =
          Enum.reduce_while(1..60, {scout_now.(), camps_before}, fn _turn, {unit, camps} ->
            discovered? = Enum.any?(camps, &(&1.tile_id == context.target_camp.tile_id))

            if unit.order == nil or discovered? do
              {:halt, {unit, camps}}
            else
              Fixtures.advance_turn(context.world)
              new_camps = latest_camps(context.play_live, camps)
              {:cont, {scout_now.(), new_camps}}
            end
          end)

        {:ok,
         context
         |> Map.put(:camps_before_arrival, camps_before)
         |> Map.put(:camps_after_arrival, camps_after)}
      end

      then_ "before the trip the camp was absent, and now it is marked on the map", context do
        refute Enum.any?(context.camps_before_arrival, &(&1.tile_id == context.target_camp.tile_id))

        marker = Enum.find(context.camps_after_arrival, &(&1.tile_id == context.target_camp.tile_id))

        assert marker != nil
        assert marker.id == context.target_camp.id
        assert marker.hp == context.target_camp.hp
        {:ok, context}
      end
    end
  end
end
