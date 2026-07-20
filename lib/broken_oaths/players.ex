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

  alias BrokenOaths.Simulation.WorldServer

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
