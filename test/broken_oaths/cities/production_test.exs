defmodule BrokenOaths.Cities.ProductionTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Cities.Production
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  # Same fixture pair as turn_test.exs/spawner_test.exs/yields_test.exs.
  # Tile 7 is flat plains (1 food / 1 production) at this seed —
  # verified by scanning every land tile — which is what gives the
  # accrual tests a worked tile with nonzero production to observe.
  @frequency 8
  @seed 424_242
  @plains_tile 7

  defp world, do: %World{seed: @seed, frequency: @frequency}

  defp city(overrides) do
    Map.merge(
      %{player_id: 1, tile_id: 1, size: 1, territory: [1], worked_tiles: [], queue: []},
      Map.new(overrides)
    )
  end

  describe "catalog/0 and cost/1" do
    test "Settler 100, Worker 60, Warrior 40, Granary 60, Bronze Spearman 60, Archer 40, Galley 50 (stories 902/903/921, QA issue da39e50b) — no Monument, no Swordsman" do
      assert Production.catalog() == %{
               settler: 100,
               worker: 60,
               warrior: 40,
               granary: 60,
               bronze_spearman: 60,
               archer: 40,
               galley: 50,
               library: 90,
               ancient_walls: 80,
               barracks: 90,
               water_mill: 90,
               pyramids: 220,
               hanging_gardens: 220
             }

      assert Production.cost(:settler) == 100
      assert Production.cost(:worker) == 60
      assert Production.cost(:warrior) == 40
      assert Production.cost(:granary) == 60
      assert Production.cost(:bronze_spearman) == 60
      assert Production.cost(:archer) == 40
      assert Production.cost(:galley) == 50
    end

    # Story 930 — Library 90 (Writing), Ancient Walls 80 (Masonry),
    # Barracks 90 (Bronze Working), Water Mill 90 (The Wheel): the
    # Granary's own 60 as the baseline, priced up for a stronger flat
    # effect than the Granary's own +2 food alone.
    test "Library 90, Ancient Walls 80, Barracks 90, Water Mill 90" do
      assert Production.cost(:library) == 90
      assert Production.cost(:ancient_walls) == 80
      assert Production.cost(:barracks) == 90
      assert Production.cost(:water_mill) == 90
    end

    # Story 933 — the Pyramids/Hanging Gardens world wonders: both cost
    # 220, priced above every standard building (see this module's own
    # moduledoc, "Story 933").
    test "Pyramids 220, Hanging Gardens 220" do
      assert Production.cost(:pyramids) == 220
      assert Production.cost(:hanging_gardens) == 220
    end
  end

  describe "unit_stats/1" do
    test "matches the 100-point HP scale for every unit type" do
      assert Production.unit_stats(:lord) == %{hp: 150, movement: 2}
      assert Production.unit_stats(:settler) == %{hp: 50, movement: 2}
      assert Production.unit_stats(:warrior) == %{hp: 100, movement: 1}
      assert Production.unit_stats(:worker) == %{hp: 10, movement: 2}
    end

    test "the Bronze Spearman (story 903): 120 HP, 1 movement — mirrors the Warrior's mobility" do
      assert Production.unit_stats(:bronze_spearman) == %{hp: 120, movement: 1}
    end

    # QA issue da39e50b "No archer" — a first-pass MELEE unit (this
    # engine has no ranged-attack model at all — see this module's own
    # moduledoc, "The Archer"): 100 HP (the Warrior's own HP), 1
    # movement, same mobility as every other Ancient-era melee unit.
    test "the Archer (QA issue da39e50b): 100 HP, 1 movement — melee-for-now, ranged attack flagged as a follow-up" do
      assert Production.unit_stats(:archer) == %{hp: 100, movement: 1}
    end

    # Story 921 — the Galley: the Warrior's own HP, but 2 movement (a
    # ship outpaces a foot soldier) — see this module's own moduledoc,
    # "The Galley".
    test "the Galley (story 921): 100 HP, 2 movement — outpaces every land unit but the Settler/Lord" do
      assert Production.unit_stats(:galley) == %{hp: 100, movement: 2}
    end
  end

  describe "can_queue?/3 (QA issue da39e50b — the Archer)" do
    test "an Archer defaults to locked — arity-2 has no research context" do
      assert Production.can_queue?(city(size: 1), :archer) == {:error, :locked}
    end

    test "refused before Archery is researched" do
      assert Production.can_queue?(city([]), :archer, archery?: false) == {:error, :locked}
    end

    test "allowed once Archery is researched" do
      assert Production.can_queue?(city([]), :archer, archery?: true) == :ok
    end

    test "every other buildable ignores the archery? option entirely" do
      assert Production.can_queue?(city(size: 2), :settler, archery?: false) == :ok
    end
  end

  describe "available_items/1 (QA issue da39e50b — the Archer)" do
    test "hidden until Archery is researched, offered once it is" do
      refute :archer in Production.available_items([])
      refute :archer in Production.available_items(archery?: false)
      assert :archer in Production.available_items(archery?: true)
    end
  end

  describe "can_queue?/3 (story 921 — the Galley)" do
    test "a Galley defaults to locked — arity-2 has no research context" do
      assert Production.can_queue?(city(size: 1), :galley) == {:error, :locked}
    end

    test "refused before Sailing is researched, even in a coastal city" do
      assert Production.can_queue?(city([]), :galley, sailing?: false, coastal?: true) ==
               {:error, :locked}
    end

    test "refused for lack of coastal water, even once Sailing is researched" do
      assert Production.can_queue?(city([]), :galley, sailing?: true, coastal?: false) ==
               {:error, :not_coastal}
    end

    test "arity-2 (no opts at all) also refuses on the coastal? default" do
      # sailing? is checked first, so the arity-2 shorthand — with
      # NEITHER option supplied — still reports the tech lock, not the
      # coastal one; the coastal-specific refusal only ever surfaces
      # once sailing? is separately satisfied (mirrors the Bronze
      # Spearman's own Copper-gate test above).
      assert Production.can_queue?(city([]), :galley) == {:error, :locked}
    end

    test "allowed once Sailing is researched AND the city is coastal" do
      assert Production.can_queue?(city([]), :galley, sailing?: true, coastal?: true) == :ok
    end

    test "every other buildable ignores the sailing?/coastal? options entirely" do
      assert Production.can_queue?(city(size: 2), :settler, sailing?: false, coastal?: false) ==
               :ok
    end
  end

  describe "available_items/1 (story 921 — the Galley)" do
    test "hidden until Sailing is researched, offered once it is — regardless of coastal? (mirrors the Bronze Spearman's own Copper posture)" do
      refute :galley in Production.available_items([])
      refute :galley in Production.available_items(sailing?: false)
      assert :galley in Production.available_items(sailing?: true)
      assert :galley in Production.available_items(sailing?: true, coastal?: false)
    end
  end

  # -------------------------------------------------------------------
  # Story 930 — Library, Ancient Walls, Barracks, Water Mill
  # -------------------------------------------------------------------

  describe "can_queue?/3 (story 930 — Library)" do
    test "a Library defaults to locked — arity-2 has no research context" do
      assert Production.can_queue?(city([]), :library) == {:error, :locked}
    end

    test "refused before Writing is researched" do
      assert Production.can_queue?(city([]), :library, library_available?: false) ==
               {:error, :locked}
    end

    test "allowed once Writing is researched" do
      assert Production.can_queue?(city([]), :library, library_available?: true) == :ok
    end

    test "refused a second time once the city already has one" do
      assert Production.can_queue?(city(buildings: [:library]), :library, library_available?: true) ==
               {:error, :already_built}
    end

    test "every other buildable ignores the option entirely" do
      assert Production.can_queue?(city(size: 2), :settler, library_available?: false) == :ok
    end
  end

  describe "can_queue?/3 (story 930 — Ancient Walls)" do
    test "refused before Masonry is researched" do
      assert Production.can_queue?(city([]), :ancient_walls, walls_available?: false) ==
               {:error, :locked}
    end

    test "allowed once Masonry is researched" do
      assert Production.can_queue?(city([]), :ancient_walls, walls_available?: true) == :ok
    end

    test "refused a second time once the city already has one" do
      assert Production.can_queue?(city(buildings: [:ancient_walls]), :ancient_walls,
               walls_available?: true
             ) == {:error, :already_built}
    end
  end

  describe "can_queue?/3 (story 930 — Barracks)" do
    test "refused before Bronze Working is researched" do
      assert Production.can_queue?(city([]), :barracks, barracks_available?: false) ==
               {:error, :locked}
    end

    test "allowed once Bronze Working is researched" do
      assert Production.can_queue?(city([]), :barracks, barracks_available?: true) == :ok
    end

    test "refused a second time once the city already has one" do
      assert Production.can_queue?(city(buildings: [:barracks]), :barracks,
               barracks_available?: true
             ) == {:error, :already_built}
    end
  end

  describe "can_queue?/3 (story 930 — Water Mill)" do
    test "refused before The Wheel is researched" do
      assert Production.can_queue?(city([]), :water_mill, water_mill_available?: false) ==
               {:error, :locked}
    end

    test "allowed once The Wheel is researched" do
      assert Production.can_queue?(city([]), :water_mill, water_mill_available?: true) == :ok
    end

    test "refused a second time once the city already has one" do
      assert Production.can_queue?(city(buildings: [:water_mill]), :water_mill,
               water_mill_available?: true
             ) == {:error, :already_built}
    end
  end

  describe "available_items/1 (story 930)" do
    test "each building is hidden until its own tech is researched, offered once it is" do
      refute :library in Production.available_items([])
      assert :library in Production.available_items(library_available?: true)

      refute :ancient_walls in Production.available_items([])
      assert :ancient_walls in Production.available_items(walls_available?: true)

      refute :barracks in Production.available_items([])
      assert :barracks in Production.available_items(barracks_available?: true)

      refute :water_mill in Production.available_items([])
      assert :water_mill in Production.available_items(water_mill_available?: true)
    end
  end

  # -------------------------------------------------------------------
  # Story 933 — the Pyramids and Hanging Gardens world wonders
  # -------------------------------------------------------------------

  describe "can_queue?/3 (story 933 — the Pyramids)" do
    test "a Pyramids defaults to locked — arity-2 has no research context" do
      assert Production.can_queue?(city([]), :pyramids) == {:error, :locked}
    end

    test "refused before Masonry is researched" do
      assert Production.can_queue?(city([]), :pyramids, pyramids_available?: false) ==
               {:error, :locked}
    end

    test "allowed once Masonry is researched and nobody has claimed it" do
      assert Production.can_queue?(city([]), :pyramids,
               pyramids_available?: true,
               pyramids_claimed?: false
             ) == :ok
    end

    test "refused once claimed anywhere in the world — no per-city :already_built check, a wonder has no per-city cap" do
      assert Production.can_queue?(city(buildings: [:pyramids]), :pyramids,
               pyramids_available?: true,
               pyramids_claimed?: true
             ) == {:error, :wonder_taken}
    end

    test "claimed takes priority over locked (a stray missing tech opt never masks the real reason)" do
      assert Production.can_queue?(city([]), :pyramids,
               pyramids_available?: false,
               pyramids_claimed?: true
             ) == {:error, :wonder_taken}
    end

    test "Hanging Gardens's own opt is untouched by the Pyramids's opts" do
      assert Production.can_queue?(city([]), :pyramids,
               pyramids_available?: true,
               pyramids_claimed?: false,
               hanging_gardens_claimed?: true
             ) == :ok
    end
  end

  describe "can_queue?/3 (story 933 — the Hanging Gardens)" do
    test "a Hanging Gardens defaults to locked — arity-2 has no research context" do
      assert Production.can_queue?(city([]), :hanging_gardens) == {:error, :locked}
    end

    test "refused before Irrigation is researched" do
      assert Production.can_queue?(city([]), :hanging_gardens, hanging_gardens_available?: false) ==
               {:error, :locked}
    end

    test "allowed once Irrigation is researched and nobody has claimed it" do
      assert Production.can_queue?(city([]), :hanging_gardens,
               hanging_gardens_available?: true,
               hanging_gardens_claimed?: false
             ) == :ok
    end

    test "refused once claimed anywhere in the world" do
      assert Production.can_queue?(city([]), :hanging_gardens,
               hanging_gardens_available?: true,
               hanging_gardens_claimed?: true
             ) == {:error, :wonder_taken}
    end
  end

  describe "available_items/1 (story 933 — the Pyramids/Hanging Gardens wonders)" do
    test "hidden until each wonder's own tech is researched" do
      refute :pyramids in Production.available_items([])
      refute :hanging_gardens in Production.available_items([])
    end

    test "offered once researched and unclaimed" do
      assert :pyramids in Production.available_items(pyramids_available?: true)
      assert :hanging_gardens in Production.available_items(hanging_gardens_available?: true)
    end

    test "dropped from the list entirely once claimed — unlike Copper/coastal's visible-but-disabled posture" do
      refute :pyramids in
               Production.available_items(pyramids_available?: true, pyramids_claimed?: true)

      refute :hanging_gardens in
               Production.available_items(
                 hanging_gardens_available?: true,
                 hanging_gardens_claimed?: true
               )
    end
  end

  describe "complete/3 (story 930)" do
    test "a Library completes into buildings: [:library] — no spawn event, no landing tile needed" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :library, banked: 90, cost: 90}])
      occupied_everywhere = %{1 => true}

      {new_city, events} = Production.complete(c, occupied_everywhere, world())

      assert new_city.buildings == [:library]
      assert new_city.queue == []
      assert events == []
    end

    test "an Ancient Walls completes into buildings: [:ancient_walls]" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :ancient_walls, banked: 80, cost: 80}])
      {new_city, events} = Production.complete(c, %{}, world())

      assert new_city.buildings == [:ancient_walls]
      assert events == []
    end

    test "a Barracks completes into buildings: [:barracks]" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :barracks, banked: 90, cost: 90}])
      {new_city, events} = Production.complete(c, %{}, world())

      assert new_city.buildings == [:barracks]
      assert events == []
    end

    test "a Water Mill completes into buildings: [:water_mill]" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :water_mill, banked: 90, cost: 90}])
      {new_city, events} = Production.complete(c, %{}, world())

      assert new_city.buildings == [:water_mill]
      assert events == []
    end

    test "a second, different building stacks onto an existing buildings list" do
      c =
        city(
          tile_id: 1,
          buildings: [:library],
          queue: [%{id: 1, type: :barracks, banked: 90, cost: 90}]
        )

      {new_city, _events} = Production.complete(c, %{}, world())
      assert Enum.sort(new_city.buildings) == [:barracks, :library]
    end

    test "a building's overflow still carries into the next queued item" do
      c =
        city(
          tile_id: 1,
          queue: [
            %{id: 1, type: :library, banked: 95, cost: 90},
            %{id: 2, type: :worker, banked: 0, cost: 60}
          ]
        )

      {new_city, _events} = Production.complete(c, %{}, world())
      assert new_city.buildings == [:library]
      assert [%{id: 2, banked: 5}] = new_city.queue
    end

    test "a below-cost building item does not complete" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :water_mill, banked: 89, cost: 90}])
      assert Production.complete(c, %{}, world()) == {c, []}
    end
  end

  describe "complete/3 (story 933 — the Hanging Gardens: passive, like every standard building)" do
    test "completes into buildings: [:hanging_gardens] — no spawn event, no landing tile needed" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :hanging_gardens, banked: 220, cost: 220}])
      occupied_everywhere = %{1 => true}

      {new_city, events} = Production.complete(c, occupied_everywhere, world())

      assert new_city.buildings == [:hanging_gardens]
      assert new_city.queue == []
      assert events == []
    end
  end

  describe "complete/3 (story 933 — the Pyramids: buildings flip AND a free Worker spawn)" do
    test "flips buildings to [:pyramids] AND spawns a free Worker via the normal landing path" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :pyramids, banked: 220, cost: 220}])
      {new_city, events} = Production.complete(c, %{}, world())

      assert new_city.buildings == [:pyramids]
      assert new_city.queue == []
      # The spawned unit's own type is :worker, deliberately NOT
      # :pyramids — the wonder itself never becomes a placed unit.
      assert events == [%{player_id: 1, type: :worker, tile_id: 1}]
    end

    test "the free Worker lands on a free adjacent tile when the city tile is occupied" do
      neighbor =
        Regions.adjacent_tiles(world(), 1)
        |> Enum.find(&(Regions.tile_class(world(), &1) == :land))

      c = city(tile_id: 1, queue: [%{id: 1, type: :pyramids, banked: 220, cost: 220}])
      occupied = %{1 => true}

      {new_city, events} = Production.complete(c, occupied, world())
      assert new_city.buildings == [:pyramids]
      assert [%{type: :worker, tile_id: landed}] = events
      refute landed == 1
      assert landed in [neighbor | Regions.adjacent_tiles(world(), 1)]
    end

    test "nothing lost when every landing tile is occupied — the wonder itself waits too, same as any other blocked spawn" do
      neighbors =
        Regions.adjacent_tiles(world(), 1)
        |> Enum.filter(&(Regions.tile_class(world(), &1) == :land))

      occupied = Map.new([1 | neighbors], &{&1, true})
      c = city(tile_id: 1, queue: [%{id: 1, type: :pyramids, banked: 220, cost: 220}])

      assert Production.complete(c, occupied, world()) == {c, []}
    end

    test "overflow carries into the next queued item, same as every other completion" do
      c =
        city(
          tile_id: 1,
          queue: [
            %{id: 1, type: :pyramids, banked: 230, cost: 220},
            %{id: 2, type: :worker, banked: 0, cost: 60}
          ]
        )

      {new_city, events} = Production.complete(c, %{}, world())
      assert new_city.buildings == [:pyramids]
      assert [%{id: 2, banked: 10}] = new_city.queue
      assert [%{type: :worker}] = events
    end
  end

  describe "accrue/3 (story 930 — the Barracks: +1 production, military queue items only)" do
    test "a military item in a Barracks city banks the extra production" do
      c = city(buildings: [:barracks], queue: [Production.new_item(:warrior)])
      accrued = Production.accrue(c, world(), %{})
      # flat base 5 + barracks 1 == 6.
      assert [%{banked: 6}] = accrued.queue
    end

    test "a Settler in the SAME Barracks city gets no bonus — the gate is on the queue item's own type" do
      c = city(buildings: [:barracks], queue: [Production.new_item(:settler)])
      accrued = Production.accrue(c, world(), %{})
      assert [%{banked: 5}] = accrued.queue
    end

    test "a building (Granary) in a Barracks city gets no bonus either" do
      c = city(buildings: [:barracks], queue: [Production.new_item(:granary)])
      accrued = Production.accrue(c, world(), %{})
      assert [%{banked: 5}] = accrued.queue
    end

    test "a military item with no Barracks gets no bonus" do
      c = city(queue: [Production.new_item(:warrior)])
      accrued = Production.accrue(c, world(), %{})
      assert [%{banked: 5}] = accrued.queue
    end
  end

  describe "accrue/3 (story 930 — the Water Mill: +1 production flat)" do
    test "every queue item in a Water Mill city banks the extra production" do
      c = city(buildings: [:water_mill], queue: [Production.new_item(:settler)])
      accrued = Production.accrue(c, world(), %{})
      # flat base 5 + water mill 1 == 6.
      assert [%{banked: 6}] = accrued.queue
    end

    test "the Barracks and Water Mill bonuses stack for a military item" do
      c = city(buildings: [:barracks, :water_mill], queue: [Production.new_item(:warrior)])
      accrued = Production.accrue(c, world(), %{})
      # flat base 5 + barracks 1 + water mill 1 == 7.
      assert [%{banked: 7}] = accrued.queue
    end
  end

  describe "barracks_production_bonus/0 and water_mill_production_bonus/0" do
    test "the public accessors match what accrue/3 actually banks" do
      assert Production.barracks_production_bonus() == 1
      assert Production.water_mill_production_bonus() == 1
    end
  end

  describe "new_item/1" do
    test "starts unbanked at the catalog cost" do
      assert Production.new_item(:warrior) == %{type: :warrior, banked: 0, cost: 40}
      assert Production.new_item(:settler) == %{type: :settler, banked: 0, cost: 100}
    end
  end

  describe "can_queue?/2" do
    test "a size-1 city cannot queue a Settler" do
      assert Production.can_queue?(city(size: 1), :settler) == {:error, :size_one}
    end

    test "a size-2+ city can queue a Settler" do
      assert Production.can_queue?(city(size: 2), :settler) == :ok
    end

    test "Worker and Warrior are always queueable" do
      assert Production.can_queue?(city(size: 1), :worker) == :ok
      assert Production.can_queue?(city(size: 1), :warrior) == :ok
    end

    test "a Granary defaults to locked — arity-2 has no research context" do
      assert Production.can_queue?(city(size: 1), :granary) == {:error, :locked}
    end
  end

  describe "can_queue?/3 (story 902 — the Granary)" do
    test "refused when Pottery isn't researched" do
      assert Production.can_queue?(city([]), :granary, granary_available?: false) ==
               {:error, :locked}
    end

    test "allowed once Pottery is researched" do
      assert Production.can_queue?(city([]), :granary, granary_available?: true) == :ok
    end

    test "refused a second time once the city already has one" do
      assert Production.can_queue?(city(has_granary: true), :granary, granary_available?: true) ==
               {:error, :already_built}
    end

    test "every other buildable ignores the option entirely" do
      assert Production.can_queue?(city(size: 2), :settler, granary_available?: false) == :ok
    end
  end

  describe "can_queue?/3 (story 903 — the Bronze Spearman)" do
    test "a Bronze Spearman defaults to locked — arity-2 has no research context" do
      assert Production.can_queue?(city(size: 1), :bronze_spearman) == {:error, :locked}
    end

    test "refused outside the Bronze Age, even with Copper access" do
      assert Production.can_queue?(city([]), :bronze_spearman,
               bronze_age?: false,
               copper_access?: true
             ) == {:error, :locked}
    end

    test "allowed once the Bronze Age is reached AND Copper access is met" do
      assert Production.can_queue?(city([]), :bronze_spearman,
               bronze_age?: true,
               copper_access?: true
             ) == :ok
    end

    test "every other buildable ignores the bronze_age? option entirely" do
      assert Production.can_queue?(city(size: 2), :settler, bronze_age?: false) == :ok
    end
  end

  describe "can_queue?/3 (story 911 — the Bronze Spearman's Copper gate)" do
    test "refused for lack of Copper access, even in the Bronze Age" do
      assert Production.can_queue?(city([]), :bronze_spearman,
               bronze_age?: true,
               copper_access?: false
             ) == {:error, :copper_required}
    end

    test "arity-2 (no opts at all) also refuses on the copper_access? default" do
      # bronze_age? is checked first, so the arity-2 shorthand — with
      # NEITHER option supplied — still reports the age lock, not the
      # Copper one; the Copper-specific refusal only ever surfaces once
      # bronze_age? is separately satisfied (see the test above).
      assert Production.can_queue?(city([]), :bronze_spearman) == {:error, :locked}
    end

    test "every other buildable ignores the copper_access? option entirely" do
      assert Production.can_queue?(city(size: 2), :settler, copper_access?: false) == :ok
    end
  end

  describe "accrue/3" do
    test "a no-op on an empty queue" do
      c = city(queue: [])
      assert Production.accrue(c, world(), %{}) == c
    end

    test "flat base alone with no worked tiles" do
      c = city(queue: [Production.new_item(:warrior)])
      accrued = Production.accrue(c, world(), %{})
      assert [%{banked: 5}] = accrued.queue
    end

    test "worked-tile production adds on top of the flat base" do
      c = city(worked_tiles: [@plains_tile], queue: [Production.new_item(:warrior)])
      accrued = Production.accrue(c, world(), %{})
      # Plains flat is 1 food / 1 production; flat base is 5.
      assert [%{banked: 6}] = accrued.queue
    end

    test "only the current (head) item banks — the rest of the queue is untouched" do
      c = city(queue: [Production.new_item(:warrior), Production.new_item(:worker)])
      accrued = Production.accrue(c, world(), %{})
      assert [%{type: :warrior, banked: 5}, %{type: :worker, banked: 0}] = accrued.queue
    end
  end

  describe "complete/3" do
    test "an item below cost does not complete" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :warrior, banked: 39, cost: 40}])
      assert Production.complete(c, %{}, world()) == {c, []}
    end

    test "an item at cost with a free city tile completes and spawns there" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :warrior, banked: 40, cost: 40}])
      {new_city, events} = Production.complete(c, %{}, world())

      assert new_city.queue == []
      assert events == [%{player_id: 1, type: :warrior, tile_id: 1}]
    end

    test "a Bronze Spearman completes and spawns exactly like a Warrior (story 903)" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :bronze_spearman, banked: 60, cost: 60}])
      {new_city, events} = Production.complete(c, %{}, world())

      assert new_city.queue == []
      assert events == [%{player_id: 1, type: :bronze_spearman, tile_id: 1}]
    end

    test "a completed item lands on a free adjacent tile when the city tile is occupied" do
      [neighbor | _] =
        Regions.adjacent_tiles(world(), 1)
        |> Enum.filter(&(Regions.tile_class(world(), &1) == :land))

      c = city(tile_id: 1, queue: [%{id: 1, type: :warrior, banked: 40, cost: 40}])
      occupied = %{1 => true}

      {_new_city, events} = Production.complete(c, occupied, world())
      assert [%{tile_id: landed}] = events
      assert landed == neighbor or landed in Regions.adjacent_tiles(world(), 1)
      refute landed == 1
    end

    test "nothing lost when every landing tile is occupied — the item just waits" do
      neighbors =
        Regions.adjacent_tiles(world(), 1)
        |> Enum.filter(&(Regions.tile_class(world(), &1) == :land))

      occupied = Map.new([1 | neighbors], &{&1, true})
      item = %{id: 1, type: :warrior, banked: 47, cost: 40}
      c = city(tile_id: 1, queue: [item])

      assert Production.complete(c, occupied, world()) == {c, []}
    end

    test "overflow carries into the next queued item" do
      c =
        city(
          tile_id: 1,
          queue: [
            %{id: 1, type: :warrior, banked: 47, cost: 40},
            %{id: 2, type: :worker, banked: 0, cost: 60}
          ]
        )

      {new_city, _events} = Production.complete(c, %{}, world())
      assert [%{id: 2, banked: 7}] = new_city.queue
    end

    test "a big overflow can cascade through more than one completion" do
      c =
        city(
          tile_id: 1,
          queue: [
            %{id: 1, type: :warrior, banked: 85, cost: 40},
            %{id: 2, type: :warrior, banked: 0, cost: 40}
          ]
        )

      {new_city, events} = Production.complete(c, %{}, world())
      assert new_city.queue == []
      assert length(events) == 2
    end

    test "a settler completion costs one population and un-works one tile" do
      c =
        city(
          tile_id: 1,
          size: 2,
          worked_tiles: [@plains_tile],
          queue: [%{id: 1, type: :settler, banked: 100, cost: 100}]
        )

      {new_city, events} = Production.complete(c, %{}, world())
      assert new_city.size == 1
      assert new_city.worked_tiles == []
      assert [%{type: :settler}] = events
    end

    test "a size-1 city's settler item waits, exactly like a blocked landing tile" do
      c = city(tile_id: 1, size: 1, queue: [%{id: 1, type: :settler, banked: 100, cost: 100}])
      assert Production.complete(c, %{}, world()) == {c, []}
    end

    test "territory is never touched by a settler's population cost" do
      c =
        city(
          tile_id: 1,
          size: 2,
          territory: [1, @plains_tile],
          worked_tiles: [@plains_tile],
          queue: [%{id: 1, type: :settler, banked: 100, cost: 100}]
        )

      {new_city, _events} = Production.complete(c, %{}, world())
      assert new_city.territory == [1, @plains_tile]
    end

    test "a Granary completes into has_granary: true — no spawn event, no landing tile needed" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :granary, banked: 60, cost: 60}])
      occupied_everywhere = %{1 => true}

      {new_city, events} = Production.complete(c, occupied_everywhere, world())

      assert new_city.has_granary == true
      assert new_city.queue == []
      assert events == []
    end

    test "a Granary's overflow still carries into the next queued item" do
      c =
        city(
          tile_id: 1,
          queue: [
            %{id: 1, type: :granary, banked: 65, cost: 60},
            %{id: 2, type: :worker, banked: 0, cost: 60}
          ]
        )

      {new_city, _events} = Production.complete(c, %{}, world())
      assert new_city.has_granary == true
      assert [%{id: 2, banked: 5}] = new_city.queue
    end

    test "a below-cost Granary item does not complete" do
      c = city(tile_id: 1, queue: [%{id: 1, type: :granary, banked: 59, cost: 60}])
      assert Production.complete(c, %{}, world()) == {c, []}
    end

    # Story 921 — the Galley: tile 26 (land, this seed/frequency) has
    # two adjacent `:coastal_water` tiles, 19 and 32 — verified against
    # `Regions` directly rather than hardcoded blind, same "real world,
    # real terrain" convention this describe block already uses.
    test "a Galley completes and lands on the lowest-id adjacent coastal_water tile — never the city's own (land) tile" do
      water =
        Regions.adjacent_tiles(world(), 26)
        |> Enum.filter(&(Regions.tile_class(world(), &1) == :coastal_water))
        |> Enum.sort()

      assert water == [19, 32]

      c = city(tile_id: 26, queue: [%{id: 1, type: :galley, banked: 50, cost: 50}])
      {new_city, events} = Production.complete(c, %{}, world())

      assert new_city.queue == []
      assert events == [%{player_id: 1, type: :galley, tile_id: 19}]
    end

    test "a Galley lands on the next free coastal_water tile once the lowest-id one is occupied" do
      c = city(tile_id: 26, queue: [%{id: 1, type: :galley, banked: 50, cost: 50}])
      occupied = %{19 => true}

      {_new_city, events} = Production.complete(c, occupied, world())
      assert events == [%{player_id: 1, type: :galley, tile_id: 32}]
    end

    test "a Galley item waits when every adjacent coastal_water tile is occupied — the city's own land tile is never used as a fallback" do
      c = city(tile_id: 26, queue: [%{id: 1, type: :galley, banked: 50, cost: 50}])
      occupied = %{19 => true, 32 => true}

      assert Production.complete(c, occupied, world()) == {c, []}
    end

    test "a landlocked city (no adjacent coastal_water) never completes a Galley" do
      # Tile 1 (the fixture's usual city tile) has no adjacent
      # coastal_water at this seed/frequency.
      refute Enum.any?(
               Regions.adjacent_tiles(world(), 1),
               &(Regions.tile_class(world(), &1) == :coastal_water)
             )

      c = city(tile_id: 1, queue: [%{id: 1, type: :galley, banked: 50, cost: 50}])
      assert Production.complete(c, %{}, world()) == {c, []}
    end
  end

  describe "validate_founding/3" do
    test "refuses ocean/mountain tiles" do
      non_land = Enum.find(0..641, &(Regions.tile_class(world(), &1) != :land))
      assert Production.validate_founding(world(), [], non_land) == {:error, :invalid_terrain}
    end

    test "an empty world has no spacing constraint" do
      assert Production.validate_founding(world(), [], 1) == :ok
    end

    test "refuses founding within 3 hexes of an existing city" do
      target = land_ring(1, 3) |> List.first()
      existing = [city(tile_id: 1)]
      assert Production.validate_founding(world(), existing, target) == {:error, :too_close}
    end

    test "allows founding exactly 4 hexes from an existing city" do
      target = land_ring(1, 4) |> List.first()
      existing = [city(tile_id: 1)]
      assert Production.validate_founding(world(), existing, target) == :ok
    end
  end

  describe "founding_territory/2" do
    test "is the tile plus every mesh-adjacent neighbor, unconditionally" do
      territory = Production.founding_territory(world(), 50)
      neighbors = Regions.adjacent_tiles(world(), 50)

      assert MapSet.size(territory) == length(neighbors) + 1
      assert MapSet.member?(territory, 50)
      assert Enum.all?(neighbors, &MapSet.member?(territory, &1))
    end
  end

  # Land-only BFS ring, exactly like the spex's own "N hexes away"
  # helpers (see e.g. criterion 7462) — used here to build concrete
  # too-close/far-enough founding targets without hardcoding tile ids.
  defp land_ring(start, depth) do
    land? = fn t -> Regions.tile_class(world(), t) == :land end

    {frontier, _seen} =
      Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
        next =
          frontier
          |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))
          |> Enum.filter(land?)

        {next, MapSet.union(seen, MapSet.new(next))}
      end)

    frontier
  end
end
