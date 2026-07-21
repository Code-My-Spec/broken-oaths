defmodule BrokenOaths.Simulation.Turn.RoadBuilderTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Simulation.Turn.RoadBuilder
  alias BrokenOaths.Worlds.World

  # Same seed/frequency (and the same tile-5 -> 9 -> 11 open-terrain
  # neighbor chain) `TurnTest` already establishes for this fixture —
  # `RoadBuilder.resolve/1` is exercised DIRECTLY here rather than
  # through `Turn.tick/1` (unlike every OTHER `Turn.*` phase in this
  # codebase, which has no dedicated per-submodule test file): a
  # brand-new road needs a real `Repo.insert` this pure module may
  # never make itself (see its own "Pure core, impure shell"
  # moduledoc), so the "what does `resolve/1` itself decide to do"
  # question is best asked directly, independent of `Cities.
  # Improvement.advance/1`'s own economy-gated progress timing (already
  # covered by `TurnTest`'s "tick/1 improvement progress" describe
  # block) and of `WorldServer.materialize_road_starts/2`'s own real
  # insert (covered end to end by `WorldServerTest`'s `build_road_to/4`
  # describe block).
  @frequency 8
  @seed 424_242

  defp world, do: %World{seed: @seed, frequency: @frequency, economy_turns: 1}

  defp unit(id, opts) do
    max_movement = Keyword.get(opts, :max_movement, 2)
    max_hp = Keyword.get(opts, :max_hp, 10)

    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      type: :worker,
      tile_id: Keyword.fetch!(opts, :tile),
      hp: Keyword.get(opts, :hp, max_hp),
      max_hp: max_hp,
      movement: Keyword.get(opts, :movement, max_movement),
      max_movement: max_movement
    }
  end

  defp base_state(units, orders, roads \\ %{}) do
    %{
      world: world(),
      turn: 0,
      units: units,
      orders: orders,
      roads: roads,
      players: %{1 => %{id: 1, user_id: 1, region_id: 0, gold: 50}},
      explored: %{},
      cities: %{},
      improvements: %{}
    }
  end

  defp road_to_order(path, hp_at_issue),
    do: %{kind: :road_to, path: path, status: :pending, hp_at_issue: hp_at_issue}

  defp building(builder_unit_id, progress \\ 0),
    do: %{status: :building, progress: progress, builder_unit_id: builder_unit_id}

  defp complete(progress \\ 2), do: %{status: :complete, progress: progress, builder_unit_id: nil}

  describe "resolve/1 walking" do
    test "steps one hex toward the first unroaded tile when not standing on it" do
      worker = unit(1, tile: 5)
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], worker.hp)})

      {new_state, events} = RoadBuilder.resolve(state)

      assert new_state.units[1].tile_id == 9
      assert events == []
      assert new_state.orders[1].path == [9, 11]
    end

    test "walks straight through an already-complete tile without touching it" do
      worker = unit(1, tile: 9)
      roads = %{9 => complete()}
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], worker.hp)}, roads)

      {new_state, _events} = RoadBuilder.resolve(state)

      assert new_state.units[1].tile_id == 11
      assert new_state.roads[9] == complete()
      refute Map.has_key?(new_state.roads, 11)
    end
  end

  describe "resolve/1 build start/resume" do
    test "emits {:road_start_needed, tile_id, unit_id} and leaves state.roads untouched with no existing row" do
      worker = unit(1, tile: 9)
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], worker.hp)})

      {new_state, events} = RoadBuilder.resolve(state)

      assert events == [{:road_start_needed, 9, 1}]
      assert new_state.roads == %{}
      # No event handler ran yet — the worker stays put, nothing walked.
      assert new_state.units[1].tile_id == 9
    end

    test "resumes an existing :building row in place — pure in-memory write, no event" do
      worker = unit(1, tile: 9)
      roads = %{9 => building(_someone_else = 42, 1)}
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], worker.hp)}, roads)

      {new_state, events} = RoadBuilder.resolve(state)

      assert events == []
      assert new_state.roads[9].builder_unit_id == 1
      assert new_state.roads[9].progress == 1
    end

    test "resumes a :pillaged row the same pure way (any non-complete status)" do
      worker = unit(1, tile: 9)
      roads = %{9 => %{status: :pillaged, progress: 1, builder_unit_id: nil}}
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], worker.hp)}, roads)

      {new_state, events} = RoadBuilder.resolve(state)

      assert events == []
      assert new_state.roads[9].status == :pillaged
      assert new_state.roads[9].builder_unit_id == 1
    end
  end

  describe "resolve/1 cancellation" do
    test "a blocked next tile cancels the whole order" do
      worker = unit(1, tile: 5)
      blocker = unit(2, tile: 9)
      state = base_state(%{1 => worker, 2 => blocker}, %{1 => road_to_order([9, 11], worker.hp)})

      {new_state, _events} = RoadBuilder.resolve(state)

      refute Map.has_key?(new_state.orders, 1)
      assert new_state.units[1].tile_id == 5
      assert new_state.units[2].tile_id == 9
    end

    test "hp dropping below hp_at_issue cancels the order before anything else runs" do
      worker = unit(1, tile: 9, hp: 6)
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], _hp_at_issue = 10)})

      {new_state, _events} = RoadBuilder.resolve(state)

      refute Map.has_key?(new_state.orders, 1)
      assert new_state.roads == %{}
      assert new_state.units[1].tile_id == 9
    end

    test "hp holding steady (or having healed above hp_at_issue) never cancels" do
      worker = unit(1, tile: 5, hp: 10)
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], _hp_at_issue = 8)})

      {new_state, _events} = RoadBuilder.resolve(state)

      assert Map.has_key?(new_state.orders, 1)
    end

    test "a dead worker's order is dropped without crashing" do
      state = base_state(%{}, %{1 => road_to_order([9, 11], 10)})

      {new_state, events} = RoadBuilder.resolve(state)

      refute Map.has_key?(new_state.orders, 1)
      assert events == []
    end
  end

  describe "resolve/1 completion" do
    test "removes the order once every tile forward of the worker is already complete" do
      worker = unit(1, tile: 11)
      roads = %{9 => complete(), 11 => complete()}
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], worker.hp)}, roads)

      {new_state, events} = RoadBuilder.resolve(state)

      refute Map.has_key?(new_state.orders, 1)
      assert events == []
      assert new_state.units[1].tile_id == 11
    end

    test "a tile complete BEHIND the worker's own position doesn't block completion — only forward tiles count" do
      # Worker is standing on the destination (11), which is complete;
      # tile 9 (behind it) is untouched (not even a road row) — the
      # "forward from current position" scan never looks back at it.
      worker = unit(1, tile: 11)
      roads = %{11 => complete()}
      state = base_state(%{1 => worker}, %{1 => road_to_order([9, 11], worker.hp)}, roads)

      {new_state, _events} = RoadBuilder.resolve(state)

      refute Map.has_key?(new_state.orders, 1)
    end
  end

  # An end-to-end trace across several `resolve/1` calls, manually
  # "materializing" a `{:road_start_needed, ...}` event between calls
  # the same way `WorldServer.materialize_road_starts/2` would for
  # real (see `RoadBuilder`'s own "Pure core, impure shell" moduledoc)
  # — proves the full walk -> build -> walk -> build -> complete
  # sequence over a 2-segment route, skipping nothing that's already
  # roaded and rebuilding nothing twice.
  describe "resolve/1 multi-segment sequencing" do
    test "roads every gap tile along the route in sequence and completes at the destination" do
      worker = unit(1, tile: 5)
      order = road_to_order([9, 11], worker.hp)
      state = base_state(%{1 => worker}, %{1 => order})

      # Step 1: walk 5 -> 9.
      {s1, e1} = RoadBuilder.resolve(state)
      assert s1.units[1].tile_id == 9
      assert e1 == []

      # Step 2: standing on 9 — requests a fresh build.
      {s2, e2} = RoadBuilder.resolve(s1)
      assert e2 == [{:road_start_needed, 9, 1}]
      assert s2.roads == %{}

      # Materialize the request (what `WorldServer` would really do).
      s2 = Map.put(s2, :roads, %{9 => building(1)})

      # Step 3: resumes tile 9 in place — imagine `Improvement.advance/1`
      # then banks it to :complete (duration 2) before the next call.
      {s3, e3} = RoadBuilder.resolve(s2)
      assert e3 == []
      assert s3.roads[9].builder_unit_id == 1
      s3 = put_in(s3.roads[9], complete())

      # Step 4: tile 9 is now roaded — walks on to the next gap, 11.
      {s4, e4} = RoadBuilder.resolve(s3)
      assert s4.units[1].tile_id == 11
      assert e4 == []
      assert s4.roads[9] == complete()

      # Step 5: standing on 11 — requests its own fresh build.
      {s5, e5} = RoadBuilder.resolve(s4)
      assert e5 == [{:road_start_needed, 11, 1}]
      s5 = Map.put(s5, :roads, Map.put(s5.roads, 11, building(1)))
      s5 = put_in(s5.roads[11], complete())

      # Step 6: every tile on the route (9 and 11) is now complete —
      # the order is done.
      {s6, e6} = RoadBuilder.resolve(s5)
      refute Map.has_key?(s6.orders, 1)
      assert e6 == []
      assert s6.roads == %{9 => complete(), 11 => complete()}
    end
  end
end
