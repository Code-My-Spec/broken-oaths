defmodule BrokenOaths.Simulation.Turn.BarbarianPhase do
  @moduledoc """
  Story 893's barbarian AI loop — the turn-pipeline phase `BrokenOaths.
  Game.Turn.tick/1` runs after production/camp-spawn completions:
  every EXISTING camp-spawned warrior (`Map.get(unit, :camp_id)` set; a
  warrior spawned earlier THIS SAME tick by `BrokenOaths.Combat.Camps`'s
  own spawn loop is not in `state.units` yet and simply waits for the
  next boundary) gets exactly one decision from `BarbarianAI.decide/6`:
  attack an adjacent player unit (`Resolver.resolve/3`, same
  simultaneous-exchange math a player's own attack uses — a barbarian
  dying pays its killer's owner `BarbarianAI.bounty_gold/0`, and a lord
  dying schedules an heir exactly like `WorldServer`'s own combat
  handler does), step one hex toward the nearest in-range target, or
  roam near its camp. `BarbarianAI.decide/6` itself never targets a
  city directly — "adjacent to a city, nothing else to attack" is still
  reported as `:hold` (see that module's own doc and its own committed
  unit test) — so THIS phase is what turns a `:hold` next to a city
  into a real assault (story 895): `CityDefense.resolve_attack/4`
  against that city, applied through `CityDefense.take_damage/3`
  (folding in `CityDefense.pillage/2` the instant HP hits 0), with
  every city a barbarian actually struck THIS tick tracked so
  `BrokenOaths.Combat.CityDefense.regen_cities/2` knows to skip its
  regen. A true hold (nothing adjacent at all) is unchanged. Entering a
  tile with a `:complete` improvement pillages it
  (`Improvement.pillage/1`). Warriors resolve in ascending unit id
  order, threading the tick's occupied-tile set so two barbarians never
  collide.

  This is genuinely cross-cutting — it orchestrates `BarbarianAI`,
  `Combat`, `CityDefense`, and heir scheduling together — with no
  single owning domain model, so it lives on the turn pipeline itself
  rather than on any one of its siblings.

  `state` throughout is the canonical tick-state described in
  `BrokenOaths.Simulation.Turn`.
  """

  alias BrokenOaths.Cities.Improvement
  alias BrokenOaths.Combat.BarbarianAI
  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Combat.Resolver
  alias BrokenOaths.Feudal.ProtectionPact
  alias BrokenOaths.Worlds.Regions

  @doc """
  Every EXISTING camp-spawned warrior gets one `BarbarianAI.decide/6`
  call, resolved in ascending unit id order (same determinism rule as
  every other phase in the tick pipeline) while threading `spawn_occupied`
  (this tick's own occupied-tile set, built by `BrokenOaths.Game.
  Production.resolve_completions/1` and `BrokenOaths.Combat.Camps.
  resolve_spawns/2`) so two barbarians in the same tick never step on
  each other, and so an already-existing barbarian can't roam or hunt
  onto a tile a spawn placed THIS SAME tick either.

  Returns `{state, attacked_city_ids}` — the second element (story 895)
  is every city THIS phase itself struck, so `BrokenOaths.Game.
  CityDefense.regen_cities/2` can skip that city's own regen this
  boundary.
  """
  @spec resolve(map(), map(), non_neg_integer()) :: {map(), MapSet.t()}
  def resolve(state, spawn_occupied, new_turn) do
    ids = for {id, unit} <- state.units, Map.get(unit, :camp_id), do: id
    occupied = MapSet.new(Map.keys(spawn_occupied))

    {state, _occupied, attacked_cities} =
      Enum.reduce(
        Enum.sort(ids),
        {state, occupied, MapSet.new()},
        &resolve_barbarian(&1, new_turn, &2)
      )

    {state, attacked_cities}
  end

  defp resolve_barbarian(id, new_turn, {state, occupied, attacked_cities}) do
    case Map.get(state.units, id) do
      nil ->
        {state, occupied, attacked_cities}

      barbarian ->
        camp_tile = camp_tile_for(state.camps, Map.get(barbarian, :camp_id))
        seed = {state.world.seed, state.turn, id}

        decision =
          BarbarianAI.decide(
            state.world,
            barbarian,
            camp_tile,
            Map.values(state.units),
            Map.values(state.cities),
            occupied: occupied,
            seed: seed
          )

        apply_barbarian_decision(decision, state, occupied, attacked_cities, barbarian, new_turn)
    end
  end

  defp camp_tile_for(_camps, nil), do: nil
  defp camp_tile_for(camps, camp_id), do: camps |> Map.get(camp_id) |> then(&(&1 && &1.tile_id))

  # Defensive: `BarbarianAI.decide/6` is handed `occupied` precisely to
  # keep it from choosing a currently-held tile, but a second, unrelated
  # player's own queued order can still claim a tile between when a
  # barbarian's decision was computed and when it's applied here (both
  # read the SAME pre-phase snapshot). Re-checking right before writing
  # the position is the one place this can be caught for certain — the
  # DB's own unique index on `(world_id, tile_id)` would otherwise raise
  # mid-transaction. A blocked barbarian simply holds this boundary.
  defp apply_barbarian_decision(
         {:move, tile},
         state,
         occupied,
         attacked_cities,
         barbarian,
         _new_turn
       ) do
    if MapSet.member?(occupied, tile) do
      {state, occupied, attacked_cities}
    else
      moved = %{barbarian | tile_id: tile, movement: 0}

      new_state =
        %{
          state
          | units: Map.put(state.units, barbarian.id, moved),
            improvements: maybe_pillage(state.improvements, tile)
        }
        |> Map.put(:roads, maybe_pillage(Map.get(state, :roads, %{}), tile))

      new_occupied = occupied |> MapSet.delete(barbarian.tile_id) |> MapSet.put(tile)
      {new_state, new_occupied, attacked_cities}
    end
  end

  # Story 895: `BarbarianAI.decide/6` reports `:hold` both for a true
  # "nothing anywhere near" hold AND for "already adjacent to a city,
  # nothing else to attack there yet" (that module's own doc/tests
  # never resolve the city fight itself — see this module's own doc).
  # This is where that second case becomes a real assault; a true hold
  # (no adjacent city either) is unchanged.
  defp apply_barbarian_decision(:hold, state, occupied, attacked_cities, barbarian, _new_turn) do
    case adjacent_city(state, barbarian) do
      nil ->
        {state, occupied, attacked_cities}

      city ->
        new_state = resolve_barbarian_city_attack(state, barbarian, city)
        {new_state, occupied, MapSet.put(attacked_cities, city.id)}
    end
  end

  defp apply_barbarian_decision(
         {:attack, target_id},
         state,
         occupied,
         attacked_cities,
         barbarian,
         new_turn
       ) do
    case Map.get(state.units, target_id) do
      nil ->
        {state, occupied, attacked_cities}

      target ->
        new_state = resolve_barbarian_attack(state, barbarian, target, new_turn)

        new_occupied =
          occupied
          |> vacate_if_gone(barbarian.tile_id, barbarian.id, new_state.units)
          |> vacate_if_gone(target.tile_id, target.id, new_state.units)

        {new_state, new_occupied, attacked_cities}
    end
  end

  defp adjacent_city(state, barbarian) do
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, barbarian.tile_id)
    Enum.find(Map.values(state.cities), &(&1.tile_id in adjacent_tile_ids))
  end

  # Same math `WorldServer.resolve_city_attack/3` uses for a stand-in
  # real player's immediate "attack" — see `CityDefense.resolve_attack/4`'s
  # doc. A barbarian that dies here (killed by the garrison's
  # counter-blow) pays its killer's owner the bounty.
  defp resolve_barbarian_city_attack(state, barbarian, city) do
    seed = {state.world.seed, state.turn, barbarian.id, city.id}
    units = Map.values(state.units)

    %{damage_to_city: dealt, damage_to_barbarian: taken} =
      CityDefense.resolve_attack(city, units, barbarian,
        seed: seed,
        attacker_aura?: lord_adjacent?(state, barbarian)
      )

    new_city = CityDefense.take_damage(city, dealt, state.turn)
    new_barbarian = %{barbarian | hp: max(barbarian.hp - taken, 0), movement: 0}

    %{
      state
      | units: apply_combat_unit(state.units, barbarian.id, new_barbarian),
        cities: Map.put(state.cities, city.id, new_city)
    }
    |> pay_bounty_if_barbarian_fell(new_barbarian, %{player_id: city.player_id})
  end

  defp vacate_if_gone(occupied, tile_id, unit_id, units) do
    if Map.has_key?(units, unit_id), do: occupied, else: MapSet.delete(occupied, tile_id)
  end

  defp maybe_pillage(improvements, tile_id) do
    case Map.get(improvements, tile_id) do
      nil -> improvements
      improvement -> Map.put(improvements, tile_id, Improvement.pillage(improvement))
    end
  end

  # Simultaneous exchange, same math a player's own attack uses
  # (`BrokenOaths.Combat.Resolver.resolve_attack/3`) — a dying defender still lands its
  # counter-blow. A barbarian that dies here pays its killer's owner
  # the bounty; a lord that dies here schedules an heir exactly like a
  # player-initiated kill would. `defender_garrisoned?` (story 895):
  # a player unit standing on its own city's tile fights back at +50%
  # here too, same as when it's the one striking out.
  #
  # Story 936: also drives the SAME `ProtectionPact` hooks
  # `Resolver.resolve_attack/4` already runs for a real player's own
  # attack, so a barbarian striking a vassal's unit raises/resolves a
  # Protection Pact call exactly like a hostile player would — this was
  # the real gap the story's bug fix closed (only the test-only
  # `resolve_barbarian_attack_for_test` bridge drove these before). The
  # one-line `Map.put(:turn, new_turn)` right before those hooks matters:
  # this whole phase runs mid-`Turn.tick/1`, BEFORE `state.turn` itself
  # is bumped to `new_turn` (see that module's own doc), so
  # `ProtectionPact.maybe_raise_protection_call/3` — which stamps a
  # freshly-raised call's deadline off `state.turn` — would otherwise
  # timestamp it one turn stale and shave a turn off the lord's response
  # window. Safe to bump here: nothing else in the tick pipeline between
  # this phase and `Turn.tick/1`'s own unconditional final
  # `Map.put(:turn, new_turn)` reads `state.turn`.
  defp resolve_barbarian_attack(state, barbarian, target, new_turn) do
    seed = {state.world.seed, state.turn, barbarian.id, target.id}

    %{damage_to_defender: dealt, damage_to_attacker: taken} =
      Resolver.resolve(barbarian, target,
        seed: seed,
        defender_aura?: lord_adjacent?(state, target),
        defender_garrisoned?: CityDefense.garrisoned?(target, Map.values(state.cities))
      )

    new_barbarian = %{barbarian | hp: max(barbarian.hp - taken, 0), movement: 0}
    new_target = %{target | hp: max(target.hp - dealt, 0)}

    units =
      state.units
      |> apply_combat_unit(barbarian.id, new_barbarian)
      |> apply_combat_unit(target.id, new_target)

    %{state | units: units}
    |> schedule_heir_if_lord_fell(target, new_target, new_turn)
    |> pay_bounty_if_barbarian_fell(new_barbarian, target)
    |> Map.put(:turn, new_turn)
    |> ProtectionPact.maybe_raise_protection_call(barbarian, target.player_id)
    |> ProtectionPact.resolve_protection_call_if_dead(new_barbarian)
    |> ProtectionPact.resolve_protection_call_if_dead(new_target)
  end

  defp apply_combat_unit(units, id, %{hp: 0}), do: Map.delete(units, id)
  defp apply_combat_unit(units, id, unit), do: Map.put(units, id, unit)

  # Story 904: same career-total bump `WorldServer.pay_bounty_if_barbarian_fell/3`
  # applies for a player-initiated kill — a barbarian-initiated exchange
  # resolved here (this AI loop's own attack, felled by the defender's
  # counter-blow) counts toward the progress panel's "Total barbarians
  # killed" figure exactly the same way.
  defp pay_bounty_if_barbarian_fell(state, %{hp: 0}, %{player_id: payee_id})
       when not is_nil(payee_id) do
    state = update_in(state.players[payee_id].gold, &(&1 + BarbarianAI.bounty_gold()))
    update_in(state.players[payee_id].barbarians_killed, &(&1 + 1))
  end

  defp pay_bounty_if_barbarian_fell(state, _barbarian, _target), do: state

  defp schedule_heir_if_lord_fell(state, %{type: :lord, player_id: player_id}, %{hp: 0}, new_turn) do
    pending_heirs = state |> Map.get(:pending_heirs, %{}) |> Map.put(player_id, new_turn + 10)
    Map.put(state, :pending_heirs, pending_heirs)
  end

  defp schedule_heir_if_lord_fell(state, _original, _new, _new_turn), do: state

  # A living unit of the SAME player standing next door — mirrors
  # `WorldServer.lord_adjacent?/2` (dead units are already gone from
  # `state.units`, so presence alone means living).
  defp lord_adjacent?(state, unit) do
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, unit.tile_id)

    state.units
    |> Map.values()
    |> Enum.any?(
      &(&1.type == :lord and &1.player_id == unit.player_id and &1.tile_id in adjacent_tile_ids)
    )
  end
end
