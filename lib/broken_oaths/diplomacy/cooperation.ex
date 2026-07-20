defmodule BrokenOaths.Diplomacy.Cooperation do
  @moduledoc """
  Cooperative-combat core (story 901): per-player damage attribution on
  a shared barbarian target, the proportional bounty split once that
  target falls, and the alliance propose/accept business rules built on
  top of `BrokenOaths.Diplomacy.Alliance`. Mirrors `BrokenOaths.Game.
  Combat`'s role: `BrokenOaths.Game.WorldServer` holds the damage
  ledger (in memory, keyed by target id) alongside its canonical
  tick-state, calls into this module on every camp-assault swing, and
  persists whatever gold `split_bounty/3` computes.

  ## Damage attribution and bounty splitting

  `contributions` is a plain map, `%{target_id => %{player_id =>
  damage_dealt}}` — every player who has struck a given target (a
  barbarian camp, at present) accumulates their own running total,
  independent of who else is also striking it and independent of a
  real turn boundary passing in between (`record_damage/4` only ever
  adds; nothing about it resets on a tick). `split_bounty/3` divides a
  reward proportionally to each contributor's own share of the total
  damage recorded — a SOLE contributor's 100% share is still the WHOLE
  reward, never a smaller "default" cut (story 901, criterion 7615) —
  using the largest-remainder method so the shares always sum to
  exactly the reward with no gold lost or invented to rounding.

  Cooperation here is emergent from shared targeting alone: nothing in
  `record_damage/4` or `split_bounty/3` looks at (or requires) an
  `Alliance` between the contributors (story 901, criterion 7624 —
  complete strangers who happen to strike the same camp still split its
  bounty by damage dealt).

  ## Alliance propose/accept

  `propose/4` and `accept/2` are the PURE state-transition rules for
  `BrokenOaths.Diplomacy.Alliance` — build (and validate) the changeset for
  proposing a new alliance or accepting an existing one, without ever
  touching `Repo`.

  `propose_alliance/3` and `accept_alliance/3` are the imperative
  wrappers around them (pragdave decomposition, slice 5 — moved home
  from `BrokenOaths.Game.WorldServer`'s own former private
  `do_propose_alliance/3`/`do_accept_alliance/3`): resolve `state`'s
  own players, look up whatever `Alliance` row already exists for the
  pair, build the changeset via `propose/4`/`accept/2` above, and
  actually perform the `Repo.insert_or_update/1`/`Repo.update/1` — an
  alliance is world-membership-scoped coordination state, not
  tick-state, so unlike a move/attack/build order these never touch
  `WorldServer`'s own `persist_tick/2` or the optimistic turn-guard
  those use. `find_alliance/3` is exposed publicly (rather than kept
  private) because `WorldServer`'s own Feudal Stewardship eligibility
  check (`accepted_ally?/3`) also needs to resolve the same
  canonical-pair lookup.
  """

  alias BrokenOaths.Diplomacy.Alliance
  alias BrokenOaths.Repo

  @type player_id :: term()
  @type target_id :: term()
  @type contributions :: %{target_id() => %{player_id() => non_neg_integer()}}

  # -------------------------------------------------------------------
  # Damage attribution and bounty splitting
  # -------------------------------------------------------------------

  @doc """
  Record `damage` dealt to `target_id` by `player_id`, adding onto
  whatever that player has already dealt to this same target.
  """
  @spec record_damage(contributions(), target_id(), player_id(), non_neg_integer()) ::
          contributions()
  def record_damage(contributions, target_id, player_id, damage) do
    Map.update(
      contributions,
      target_id,
      %{player_id => damage},
      &Map.update(&1, player_id, damage, fn total -> total + damage end)
    )
  end

  @doc """
  Split `total_reward` among every player who dealt damage to
  `target_id`, proportional to each one's own share of the total damage
  recorded — `%{player_id => gold}`. A target with no recorded damage
  (never struck, or already forgotten via `forget/2`) splits nothing:
  `%{}`. The largest-remainder method guarantees `Enum.sum(Map.values(result))
  == total_reward` exactly.
  """
  @spec split_bounty(contributions(), target_id(), pos_integer()) :: %{player_id() => pos_integer()}
  def split_bounty(contributions, target_id, total_reward) do
    contributions
    |> Map.get(target_id, %{})
    |> proportional_split(total_reward)
  end

  @doc "Drop `target_id`'s damage ledger — call once its bounty has been paid out."
  @spec forget(contributions(), target_id()) :: contributions()
  def forget(contributions, target_id), do: Map.delete(contributions, target_id)

  defp proportional_split(damage_by_player, _total_reward) when map_size(damage_by_player) == 0,
    do: %{}

  defp proportional_split(damage_by_player, total_reward) do
    total_damage = damage_by_player |> Map.values() |> Enum.sum()

    shares =
      for {player_id, damage} <- damage_by_player do
        exact = damage * total_reward / total_damage
        {player_id, trunc(exact), exact - trunc(exact)}
      end

    remainder = total_reward - (shares |> Enum.map(&elem(&1, 1)) |> Enum.sum())

    shares
    # Largest fractional remainder first; ties broken by player_id for a
    # deterministic result regardless of map iteration order.
    |> Enum.sort_by(fn {player_id, _base, frac} -> {-frac, player_id} end)
    |> Enum.with_index()
    |> Map.new(fn {{player_id, base, _frac}, index} ->
      {player_id, base + if(index < remainder, do: 1, else: 0)}
    end)
  end

  # -------------------------------------------------------------------
  # Alliance propose/accept — pure rules
  # -------------------------------------------------------------------

  @doc """
  Build the changeset proposing an alliance between `proposer_player_id`
  and `other_player_id` in `world_id`. `existing` is whatever alliance
  already exists for this pair (`nil` if none) — proposing again once
  one already exists is refused rather than silently duplicated.
  """
  @spec propose(Alliance.t() | nil, term(), player_id(), player_id()) ::
          {:ok, Ecto.Changeset.t()} | {:error, :already_proposed | :already_allied}
  def propose(nil, world_id, proposer_player_id, other_player_id) do
    {:ok,
     Alliance.changeset(%Alliance{}, %{
       world_id: world_id,
       player_a_id: proposer_player_id,
       player_b_id: other_player_id,
       proposer_player_id: proposer_player_id,
       status: :proposed
     })}
  end

  def propose(%Alliance{status: :proposed}, _world_id, _proposer_player_id, _other_player_id),
    do: {:error, :already_proposed}

  def propose(%Alliance{status: :accepted}, _world_id, _proposer_player_id, _other_player_id),
    do: {:error, :already_allied}

  @doc """
  Build the changeset accepting `alliance` — refused unless
  `accepting_player_id` is the OTHER party (never the original
  proposer) and the alliance is still `:proposed`.
  """
  @spec accept(Alliance.t(), player_id()) ::
          {:ok, Ecto.Changeset.t()}
          | {:error, :already_accepted | :self_accept | :not_a_party}
  def accept(%Alliance{status: :accepted}, _accepting_player_id), do: {:error, :already_accepted}

  def accept(%Alliance{proposer_player_id: proposer_id}, accepting_player_id)
      when accepting_player_id == proposer_id,
      do: {:error, :self_accept}

  def accept(%Alliance{player_a_id: a, player_b_id: b} = alliance, accepting_player_id)
      when accepting_player_id in [a, b] do
    {:ok, Alliance.changeset(alliance, %{status: :accepted})}
  end

  def accept(_alliance, _accepting_player_id), do: {:error, :not_a_party}

  # -------------------------------------------------------------------
  # Alliance propose/accept — imperative wrappers (see this module's
  # own "Alliance propose/accept" moduledoc section above).
  # -------------------------------------------------------------------

  @doc "Resolve `user`/`other_user` against `state`, then `propose/4` + persist."
  @spec propose_alliance(map(), map(), map()) :: {:ok, Alliance.t()} | {:error, atom()}
  def propose_alliance(state, user, other_user) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, other_player} <- fetch_player(state, other_user.id),
         existing = find_alliance(state.world.id, player.id, other_player.id),
         {:ok, changeset} <-
           propose(existing, state.world.id, player.id, other_player.id) do
      Repo.insert_or_update(changeset)
    end
  end

  @doc "Resolve `user` and the target `alliance_id`, then `accept/2` + persist."
  @spec accept_alliance(map(), map(), term()) :: {:ok, Alliance.t()} | {:error, atom()}
  def accept_alliance(state, user, alliance_id) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, alliance} <- fetch_alliance(alliance_id),
         {:ok, changeset} <- accept(alliance, player.id) do
      Repo.update(changeset)
    end
  end

  @doc """
  The `Alliance` row for the unordered `(player_a_id, player_b_id)` pair
  in `world_id`, or `nil` — reads back the same canonical (lowest id,
  highest id) order `Alliance.changeset/2` itself normalizes to, so the
  caller never has to reason about which of the two is "me". Public: also
  read by `WorldServer`'s own Feudal Stewardship `:ally` eligibility check.
  """
  @spec find_alliance(term(), player_id(), player_id()) :: Alliance.t() | nil
  def find_alliance(world_id, player_a_id, player_b_id) do
    {lo, hi} =
      if player_a_id <= player_b_id,
        do: {player_a_id, player_b_id},
        else: {player_b_id, player_a_id}

    Repo.get_by(Alliance, world_id: world_id, player_a_id: lo, player_b_id: hi)
  end

  defp fetch_alliance(alliance_id) do
    case Repo.get(Alliance, alliance_id) do
      nil -> {:error, :not_found}
      alliance -> {:ok, alliance}
    end
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer`, matching the sibling `BrokenOaths.Units.Unit`/
  # `BrokenOaths.Vision.Visibility`'s own "pure, process-unaware,
  # unit-testable with no GenServer running" contract (small private
  # helper copies rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp fetch_player(state, user_id) do
    case find_player(state, user_id) do
      nil -> {:error, :not_a_player}
      player -> {:ok, player}
    end
  end
end
