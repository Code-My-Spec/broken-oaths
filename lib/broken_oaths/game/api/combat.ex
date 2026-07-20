defmodule BrokenOaths.Game.API.Combat do
  @moduledoc """
  Attack orders (unit-vs-unit, camp assault, city siege), garrison
  fate, and the barbarian-camp ground-truth/test seams. Thin
  `GenServer.call` wrappers onto each world's `BrokenOaths.Game.WorldServer`;
  see `BrokenOaths.Game`'s own moduledoc for the process architecture
  every function here round-trips through.

  Extracted from `BrokenOaths.Game` (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target) — every function below is
  `defdelegate`d back onto `BrokenOaths.Game` unchanged, so no caller
  needs to know this module exists.
  """

  alias BrokenOaths.Game.WorldServer

  @doc """
  Order `unit_id` to attack `target_unit_id`: adjacent, hostile
  (barbarian) targets only — see `BrokenOaths.Game.Combat` for the
  legality rules and damage math. Resolves immediately, like
  `queue_move/4`, and spends all of the attacker's remaining movement.
  """
  @spec attack(map(), map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: pos_integer()}}
          | {:error,
             :not_owner
             | :invalid_target
             | :out_of_movement
             | :not_adjacent
             | :not_hostile}
  def attack(world, user, unit_id, target_unit_id),
    do: WorldServer.call(world, {:attack, user, unit_id, target_unit_id})

  @doc """
  Order `unit_id` to attack `camp_id` (story 894): adjacent, not yet
  destroyed camps only. Flat damage (`Game.Combat.camp_damage/2`, no
  counter) — resolves immediately, like `attack/4`. A camp reduced to 0
  HP is destroyed: `user` is paid `Game.Camps.destroy_reward/0` gold,
  the camp stops spawning and disappears from `camps_visible_to/2`, and
  its former tile is ordinary land again.
  """
  @spec attack_camp(map(), map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: 0}}
          | {:error, :not_owner | :invalid_target | :out_of_movement | :not_adjacent}
  def attack_camp(world, user, unit_id, camp_id),
    do: WorldServer.call(world, {:attack_camp, user, unit_id, camp_id})

  @doc """
  Order `unit_id` to attack `city_id` (story 895): adjacent, not the
  attacker's own city. Resolves immediately, like `attack/4` — damage
  to the city's own HP (pillaged, not captured, at 0 — see
  `BrokenOaths.Game.CityDefense`) and counter-attack damage the
  attacker takes from the city's strongest garrisoned defender (0 if
  undefended).
  """
  @spec attack_city(map(), map(), term(), term()) ::
          {:ok, %{damage_dealt: non_neg_integer(), damage_taken: non_neg_integer()}}
          | {:error,
             :not_owner
             | :invalid_target
             | :out_of_movement
             | :not_adjacent
             | :own_city
             | :not_military
             | :not_hostile}
  def attack_city(world, user, unit_id, city_id),
    do: WorldServer.call(world, {:attack_city, user, unit_id, city_id})

  @doc """
  Resolve the conqueror's own execute-or-release choice for a captured
  city's fallen garrison (story 906): `choice` is `:release` (the
  garrison survives untouched) or `:execute` (removed from the board).
  `user` must be `city_id`'s own captor.
  """
  @spec resolve_garrison_fate(map(), map(), term(), :release | :execute) ::
          :ok | {:error, :invalid_target | :not_owner}
  def resolve_garrison_fate(world, user, city_id, choice),
    do: WorldServer.call(world, {:resolve_garrison_fate, user, city_id, choice})

  @doc """
  Every barbarian camp in `world`, unfiltered ground truth (never
  fog-filtered) — see `BrokenOathsSpex.Fixtures.list_camps/1`'s doc for
  why this sanctioned, no-UI-surface read exists (same status as
  `Worlds.Regions.partition/1`). Never call this to decide what a
  player sees; use `camps_visible_to/2` for that.
  """
  def list_camps(world), do: WorldServer.call(world, :list_camps)

  @doc """
  Test-only: place a real barbarian warrior directly on `tile_id` — see
  `BrokenOaths.Game.WorldServer`'s `:spawn_barbarian_for_test` handler
  for the same documented, narrow-exception status `set_unit_hp_for_test/3`
  already has. `camp_id` (nil by default — ownerless, no AI, story 891's
  original behavior) ties the warrior to a REAL camp so story 893's
  barbarian AI drives it for real from the next boundary. Returns the
  spawned unit's map (`id`, `tile_id`, `hp`, ...).
  """
  @spec spawn_barbarian_for_test(map(), term(), term()) :: map()
  def spawn_barbarian_for_test(world, tile_id, camp_id \\ nil),
    do: WorldServer.call(world, {:spawn_barbarian_for_test, tile_id, camp_id})

  @doc """
  Test-only: move a barbarian directly onto `tile_id`, applying
  `Turn`'s own pillage-on-entry rule as a single isolated write rather
  than a full tick boundary — see `BrokenOaths.Game.WorldServer`'s
  `:move_barbarian_for_test` handler for the same documented,
  narrow-exception status. `:ok` or `{:error, :occupied}`.
  """
  @spec move_barbarian_for_test(map(), term(), term()) :: :ok | {:error, :occupied}
  def move_barbarian_for_test(world, barbarian_id, tile_id),
    do: WorldServer.call(world, {:move_barbarian_for_test, barbarian_id, tile_id})

  @doc """
  Test-only: destroy every camp except `keep_camp_id` and hard-delete
  every unit already tied to one of those other camps — see
  `BrokenOaths.Game.WorldServer`'s `:isolate_camp_for_test` handler for
  the same documented, narrow-exception status.
  """
  @spec isolate_camp_for_test(map(), term()) :: :ok
  def isolate_camp_for_test(world, keep_camp_id),
    do: WorldServer.call(world, {:isolate_camp_for_test, keep_camp_id})

  @doc """
  Test-only: hard-delete every warrior currently tied to `camp_id`,
  without touching the camp itself — see `BrokenOaths.Game.WorldServer`'s
  `:clear_camp_warriors_for_test` handler for the same documented,
  narrow-exception status.
  """
  @spec clear_camp_warriors_for_test(map(), term()) :: :ok
  def clear_camp_warriors_for_test(world, camp_id),
    do: WorldServer.call(world, {:clear_camp_warriors_for_test, camp_id})

  @doc """
  Test-only: resolve an attack FROM a barbarian (no owning player/session
  exists to drive this through `attack/4`) — see
  `BrokenOaths.Game.WorldServer`'s `:resolve_barbarian_attack_for_test`
  handler for the same documented, narrow-exception status
  `spawn_barbarian_for_test/2` has.
  """
  @spec resolve_barbarian_attack_for_test(map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: pos_integer()}} | {:error, atom()}
  def resolve_barbarian_attack_for_test(world, attacker_unit_id, target_unit_id),
    do:
      WorldServer.call(
        world,
        {:resolve_barbarian_attack_for_test, attacker_unit_id, target_unit_id}
      )

  @doc """
  Dev-only QA control surface: set `camp_id`'s HP directly, bypassing
  combat — see `BrokenOaths.Game.WorldServer`'s `:set_camp_hp_for_test`
  handler for the same documented, narrow-exception status
  `set_unit_hp_for_test/3` has.
  """
  @spec set_camp_hp_for_test(map(), term(), non_neg_integer()) :: :ok
  def set_camp_hp_for_test(world, camp_id, hp),
    do: WorldServer.call(world, {:set_camp_hp_for_test, camp_id, hp})
end
