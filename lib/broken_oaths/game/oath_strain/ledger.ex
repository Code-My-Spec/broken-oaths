defmodule BrokenOaths.Game.OathStrain.Ledger do
  @moduledoc """
  Pure, process-unaware APPLICATION of `BrokenOaths.Game.OathStrain`'s
  math across the `BrokenOaths.Game.Vassalage` rows in the WorldServer's
  own tick-`state` — the pragdave-pattern "domain model" home for the
  Oath Strain orchestration `BrokenOaths.Game.WorldServer` used to bury
  inline (see `.code_my_spec/knowledge/genserver_decomposition.md`).

  `BrokenOaths.Game.OathStrain` itself stays a PURE math module (no
  `Repo`, no process state) exactly as it already documents itself —
  this module is the imperative shell its own moduledoc anticipates:
  it reads a `Vassalage.oath_strain`, calls one of `OathStrain`'s
  drivers, and persists the result. Every function here takes the
  WorldServer's own tick-`state` (or the relevant substructure) plus
  plain args and returns either a reply tuple/value or an updated
  `state` — no `GenServer`, no `handle_*`, no process awareness.
  `WorldServer`'s own `handle_call`/tick clauses are thin one-line
  delegations into this module.

  Owns: the turn-boundary tribute-rate drift sweep (`apply_oath_strain_drift/1`,
  story 913), a lord's one-off gift to a vassal (`gift_vassal/3`), a
  lord and vassal declaring a shared enemy (`declare_shared_enemy/4`),
  and the vassal's own narrow seam for marking their lord's Protection
  Pact unhonored (`mark_pact_unhonored/3`, criterion 7722 — distinct
  from the real Protection Pact engine's own `BrokenOaths.Game.
  ProtectionPact` resolution).
  """

  import Ecto.Query

  alias BrokenOaths.Game
  alias BrokenOaths.Game.OathStrain
  alias BrokenOaths.Game.Vassalage
  alias BrokenOaths.Repo

  # -------------------------------------------------------------------
  # Turn-boundary drift (story 913)
  # -------------------------------------------------------------------

  @doc """
  Runs every turn boundary, alongside every other tick phase — drifts
  every ACTIVE vassalage's own `oath_strain` toward reflecting its
  `tribute_rate`'s own imbalance (`OathStrain.tribute_drift/2`),
  persisted only when the drift is genuinely non-zero. A no-op while
  `Game.feudal_enabled?/0` reads `false`.
  """
  @spec apply_oath_strain_drift(map()) :: map()
  def apply_oath_strain_drift(state) do
    if Game.feudal_enabled?() do
      for vassalage <- active_vassalages(state.world.id) do
        new_strain = OathStrain.tribute_drift(vassalage.oath_strain, vassalage.tribute_rate)

        if new_strain != vassalage.oath_strain do
          Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update!()
        end
      end

      state
    else
      state
    end
  end

  defp active_vassalages(world_id) do
    Vassalage
    |> where([v], v.world_id == ^world_id and v.status == :active)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Lord-driven eases (story 913)
  # -------------------------------------------------------------------

  @doc "Story 913: `user` (the lord) gifts `vassal_user_id` — eases their Oath Strain by `OathStrain.gift_ease/0`."
  @spec gift_vassal(map(), map(), integer()) :: {:ok, Vassalage.t()} | {:error, atom()}
  def gift_vassal(state, user, vassal_user_id) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      new_strain = OathStrain.ease_gift(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
    end
  end

  @doc """
  Story 913: `user` (the lord) and `vassal_user_id` declare
  `enemy_user_id` a shared enemy — eases the vassal's Oath Strain by
  `OathStrain.ease_shared_enemy/1`. `enemy_user_id` only needs to be a
  real, known player — nothing about the declaration itself is
  persisted beyond the strain ease.
  """
  @spec declare_shared_enemy(map(), map(), integer(), integer()) ::
          {:ok, Vassalage.t()} | {:error, atom()}
  def declare_shared_enemy(state, user, vassal_user_id, enemy_user_id) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, _enemy_player} <- fetch_player(state, enemy_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      new_strain = OathStrain.ease_shared_enemy(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
    end
  end

  @doc """
  Story 913 (criterion 7722): `user` (the vassal) marks their own bond
  with `lord_user_id` unhonored — spikes their own Oath Strain by
  `OathStrain.spike_broken_protection_pact/1`. Distinct from the REAL
  Protection Pact engine (`BrokenOaths.Game.ProtectionPact`, story 914) —
  this handler only ever touches Oath Strain, never the lord's Honor or
  fellow-vassal contagion.
  """
  @spec mark_pact_unhonored(map(), map(), integer()) :: {:ok, Vassalage.t()} | {:error, atom()}
  def mark_pact_unhonored(state, user, lord_user_id) do
    with {:ok, vassal_player} <- fetch_player(state, user.id),
         {:ok, lord_player} <- fetch_player(state, lord_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      new_strain = OathStrain.spike_broken_protection_pact(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
    end
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer` (or reaching sideways into `Vassalage`, out of scope
  # for this slice), matching this module's own "pure, process-unaware,
  # unit-testable with no GenServer running" contract.
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

  defp fetch_vassalage(state, lord_player_id, vassal_player_id) do
    case Repo.get_by(Vassalage,
           world_id: state.world.id,
           lord_player_id: lord_player_id,
           vassal_player_id: vassal_player_id,
           status: :active
         ) do
      nil -> {:error, :not_a_vassal}
      vassalage -> {:ok, vassalage}
    end
  end
end
