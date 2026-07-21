defmodule BrokenOaths.Diplomacy do
  @moduledoc """
  Discovery/known-players and alliance/cooperation. Thin
  `GenServer.call` wrappers onto each world's `BrokenOaths.Simulation.WorldServer`;
  see `BrokenOaths.Game`'s own moduledoc for the process architecture
  every function here round-trips through. (Chat lives in its own
  separate context already — see `BrokenOaths.Chat` — and stays there.)

  Extracted from `BrokenOaths.Game` (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target) — every function below is
  `defdelegate`d back onto `BrokenOaths.Game` unchanged, so no caller
  needs to know this module exists.
  """

  alias BrokenOaths.Simulation.WorldServer

  @doc """
  Every civilization `user` has discovered in `world` (story 899):
  `[%{user_id:, email:}]`. Permanent once recorded — unrelated to
  current fog of war, see `BrokenOaths.Diplomacy.Discovery` and
  `BrokenOaths.Diplomacy.KnownPlayer`.
  """
  def known_players(world, user), do: WorldServer.call(world, {:known_players, user})

  @doc """
  Every alliance (`:proposed` or `:accepted`) `user` is a party to in
  `world` (story 901) — `[%{id:, status:, proposed_by_me?:,
  other_user_id:, other_name:}]`, the OTHER party's identity resolved
  for each row so `GameLive.AlliancePanel` never has to cross-reference
  a raw `player_id` itself. See `BrokenOaths.Diplomacy.Alliance` and
  `BrokenOaths.Diplomacy.Cooperation`'s propose/accept business rules —
  cooperative bounty splitting on a shared barbarian kill never
  requires one of these rows to exist (criterion 7624); an alliance is
  purely the player-facing coordination signal this panel surfaces.
  """
  @spec alliances(map(), map()) :: [map()]
  def alliances(world, user), do: WorldServer.call(world, {:alliances, user})

  @doc """
  Propose an alliance between `user` and `other_user` in `world` —
  refused if either isn't a member, or a proposal/alliance between the
  two already exists (`BrokenOaths.Diplomacy.Cooperation.propose/4`).
  """
  @spec propose_alliance(map(), map(), map()) ::
          :ok
          | {:error, :not_a_player | :already_proposed | :already_allied | Ecto.Changeset.t()}
  def propose_alliance(world, user, other_user),
    do: WorldServer.call(world, {:propose_alliance, user, other_user})

  @doc """
  Accept `alliance_id`, a pending alliance `user` is the (non-proposing)
  other party to (`BrokenOaths.Diplomacy.Cooperation.accept/2`).
  """
  @spec accept_alliance(map(), map(), term()) ::
          :ok
          | {:error,
             :not_found
             | :not_a_party
             | :self_accept
             | :already_accepted
             | Ecto.Changeset.t()}
  def accept_alliance(world, user, alliance_id),
    do: WorldServer.call(world, {:accept_alliance, user, alliance_id})
end
