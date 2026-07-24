defmodule BrokenOaths.Players do
  @moduledoc """
  A player's own treasury and lifetime stats within a world. Thin
  `GenServer.call` wrappers onto each world's `BrokenOaths.Simulation.WorldServer`;
  see `BrokenOaths.Game`'s own moduledoc for the process architecture
  every function here round-trips through.

  Extracted from `BrokenOaths.Game` (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target) — every function below is
  `defdelegate`d back onto `BrokenOaths.Game` unchanged, so no caller
  needs to know this module exists.
  """

  import Ecto.Query
  alias BrokenOaths.Repo
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Simulation.WorldServer

  @doc """
  The ids of every world `user` already has a civilization in — a direct DB
  read (no WorldServer boot), used by onboarding to resume an existing
  membership before placing the user anywhere new.
  """
  @spec member_world_ids(map()) :: [integer()]
  def member_world_ids(user),
    do: Repo.all(from p in Player, where: p.user_id == ^user.id, select: p.world_id)

  @doc """
  Every home `region_id` claimed by a player in `world` — a direct DB read (no
  WorldServer boot), used by the lobby's occupancy check (`Game.world_full?/1`)
  so rendering the world picker never has to spin up a live simulation.
  """
  @spec region_ids(map()) :: [integer()]
  def region_ids(world),
    do: Repo.all(from p in Player, where: p.world_id == ^world.id, select: p.region_id)

  @doc "`user`'s current gold in `world`."
  def gold(world, user), do: WorldServer.call(world, {:gold, user})

  @doc """
  `user`'s lifetime combat totals in `world` (story 904): `%{
  barbarians_killed:, camps_destroyed:}`, or `nil` if `user` hasn't
  joined `world` — the two running counts a `BrokenOaths.Players.Player`
  row itself has to carry (unlike cities founded, which is just
  `length(player_cities/2)`; no city is ever deleted in this
  codebase). Bumped alongside the gold a barbarian bounty or a camp's
  destroy-reward already pays (`attack/4`, `attack_camp/4`, and
  `Turn`'s own barbarian-initiated exchanges), so this always stays in
  lockstep with `gold/2`.
  """
  @spec player_stats(map(), map()) ::
          %{barbarians_killed: non_neg_integer(), camps_destroyed: non_neg_integer()} | nil
  def player_stats(world, user), do: WorldServer.call(world, {:player_stats, user})
end
