defmodule BrokenOaths.Game.Cooperation do
  @moduledoc """
  Pure cooperative-combat core (story 901): per-player damage
  attribution on a shared barbarian target, the proportional bounty
  split once that target falls, and the alliance propose/accept
  business rules built on top of `BrokenOaths.Game.Alliance`. No
  `Repo`, no process state — mirrors `BrokenOaths.Game.Combat`'s role:
  `BrokenOaths.Game.WorldServer` holds the damage ledger (in memory,
  keyed by target id) alongside its canonical tick-state, calls into
  this module on every camp-assault swing, and persists whatever gold
  `split_bounty/3` computes.

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

  `propose/4` and `accept/2` are the state-transition rules for
  `BrokenOaths.Game.Alliance` — build (and validate) the changeset for
  proposing a new alliance or accepting an existing one, without ever
  touching `Repo`. The caller (a future `Game.propose_alliance/3`-style
  wrapper) is responsible for the actual read/write.
  """

  alias BrokenOaths.Game.Alliance

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
  # Alliance propose/accept
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
end
