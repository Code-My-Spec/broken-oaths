defmodule BrokenOaths.Game.Stewardship do
  @moduledoc """
  Feudal + alliance stewardship core (story 910): pure business rules
  on top of `BrokenOaths.Game.Vassalage` (907) and `BrokenOaths.Game.
  Alliance` (899/901) — mirrors `BrokenOaths.Game.Cooperation`/
  `BrokenOaths.Game.Vassalization`'s own "pure changeset/decision
  logic, no `Repo`" role. `BrokenOaths.Game.WorldServer` is the
  imperative shell: it resolves the DB-backed relationship facts (who's
  whose lord, who's allied with whom, who's currently online —
  `BrokenOaths.Game.Presence`) into the plain values this module's own
  functions take, applies the resulting decision, and persists the
  outcome (a `state.players` diff via the usual `persist_tick/2` path
  for a bank sweep/emergency move, an immediate `BrokenOaths.Game.
  StewardLog` insert for the audit trail).

  ## Who may steward whom

  `steward_role/4` resolves the ONE relationship that matters for a
  given (steward, owner) pair into `:lord | :fellow_vassal | :ally |
  :none` — the household lattice the design doc calls for
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"): the owner's own LORD, a FELLOW VASSAL sworn to
  that same lord, or an ALLY (`Alliance`, `:accepted`) may all act;
  nobody else. `eligible?/1` is the single yes/no gate every steward
  command checks first. The one asymmetry this story keeps: a vassal
  never stewards their own lord — `steward_role/4` only ever resolves
  `:lord` in the direction "owner is a vassal, steward is their lord,"
  never the reverse, so there is no clause anywhere that could match a
  vassal acting on their own lord's behalf. Alliance stewardship is the
  mirror opposite: `:ally` resolves identically regardless of which
  side is asking — `steward_role/4`'s own `allied?` argument is already
  symmetric (an accepted `Alliance` has no "up"/"down"), so either
  party stewards the other exactly the same way.

  ## What a steward may do

  Three actions, each constructive-only or defensive-only by
  construction — never a blank check:

    * **Bank sweep** — `BrokenOaths.Game.Bank.steward_collect/1` (not
      this module's own job; stewardship only decides WHO may call it
      and WHEN, `Bank` decides what collecting actually moves).
    * **Production stewardship** — `constructive_item?/1` is the safe
      whitelist gate: every unit/building this codebase can build today
      is economic or defensive by nature (no aggression-only item
      exists yet), so the whitelist is really "a legitimate build order
      at all" — cancelling an in-progress item or disbanding a unit are
      not whitelist violations to REFUSE via this gate, they are
      different COMMANDS this module never defines a path for at all
      (no `cancel`/`disband` function exists here — "no disbanding, no
      cancel-griefing" is enforced structurally, by absence, not by a
      runtime check).
    * **Emergency defense** — `under_attack?/1` is the gate: normally a
      steward cannot touch the offline owner's units at all; only while
      at least one of the owner's own units carries live damage (`hp <
      max_hp` — the most literal, observable "under attack" signal
      available; see story 910's own spec fixtures) does the window
      open, and even then only for a genuinely DEFENSIVE reposition —
      `defend_target_allowed?/3` refuses anything beyond one hex from
      the unit's own current tile, so the emergency window can never be
      used to march the army off or launch it at a target (aggression
      has no path through this module at all, same "enforced by
      absence" discipline production cancel/disband has above).

  ## Anti-sabotage

  `log_attrs/7` is the one shared shape every steward action's own
  `StewardLog` insert builds from — every action, successful or
  refused-as-overreach, gets a row so the owner can review the full
  history on return (criterion 7695). `apply_sabotage_penalty/1` is the
  Honor consequence: a steward who abuses the emergency window (an
  `under_attack?/1`-gated attempt that still fails `defend_target_allowed?/3`)
  is provable sabotage the moment it's attempted, whether or not the
  underlying move itself is also blocked — `sabotage_honor_penalty/0`
  is the fixed, small, tunable ding (mirrors `Tribute.
  oath_strain_refusal_spike/0`'s own "a fixed, documented, callable
  constant" status).
  """

  alias BrokenOaths.Game.StewardLog

  @type player_id :: term()
  @type role :: :lord | :fellow_vassal | :ally | :none
  @type unit :: %{hp: integer(), max_hp: integer()}

  @constructive_items [:settler, :worker, :warrior, :granary, :bronze_spearman]
  @sabotage_honor_penalty 2

  # -------------------------------------------------------------------
  # Who may steward whom
  # -------------------------------------------------------------------

  @doc """
  Resolves the (steward, owner) relationship into a `role/0` —
  `owner_lord_id` is the lord of `owner`'s own active `Vassalage` (as
  vassal), or `nil` if `owner` isn't presently anyone's vassal;
  `steward_lord_id` is the same fact for `steward_player_id`;
  `allied?` is whether an ACCEPTED `Alliance` exists between the two
  (already symmetric — the caller resolves it once, not per-direction).
  """
  @spec steward_role(player_id() | nil, player_id(), player_id() | nil, boolean()) :: role()
  def steward_role(owner_lord_id, steward_player_id, _steward_lord_id, _allied?)
      when not is_nil(owner_lord_id) and owner_lord_id == steward_player_id,
      do: :lord

  def steward_role(owner_lord_id, _steward_player_id, steward_lord_id, _allied?)
      when not is_nil(owner_lord_id) and not is_nil(steward_lord_id) and
             owner_lord_id == steward_lord_id,
      do: :fellow_vassal

  def steward_role(_owner_lord_id, _steward_player_id, _steward_lord_id, true), do: :ally
  def steward_role(_owner_lord_id, _steward_player_id, _steward_lord_id, _allied?), do: :none

  @doc "Whether `role` may steward at all — every role except `:none`."
  @spec eligible?(role()) :: boolean()
  def eligible?(:none), do: false
  def eligible?(_role), do: true

  # -------------------------------------------------------------------
  # Production stewardship
  # -------------------------------------------------------------------

  @doc "Whether `type` is on the constructive-only production whitelist a steward may queue."
  @spec constructive_item?(atom()) :: boolean()
  def constructive_item?(type), do: type in @constructive_items

  # -------------------------------------------------------------------
  # Emergency defense
  # -------------------------------------------------------------------

  @doc """
  Whether the offline owner counts as "under attack" right now — at
  least one of their own units currently carries live damage (`hp <
  max_hp`). The emergency-defense window's own gate.
  """
  @spec under_attack?([unit()]) :: boolean()
  def under_attack?(units), do: Enum.any?(units, &(&1.hp < &1.max_hp))

  @doc """
  Whether `to_tile` is a genuinely DEFENSIVE reposition for a unit
  standing on `current_tile_id` — strictly one of `adjacent_tile_ids`
  (mesh-adjacent to where it already is) and never the tile it's
  already standing on. Refuses both marching the army off (any
  farther tile) and a no-op "defend in place."
  """
  @spec defend_target_allowed?(term(), term(), [term()]) :: boolean()
  def defend_target_allowed?(current_tile_id, to_tile, adjacent_tile_ids),
    do: to_tile != current_tile_id and to_tile in adjacent_tile_ids

  # -------------------------------------------------------------------
  # Anti-sabotage
  # -------------------------------------------------------------------

  @doc "How much a provable-sabotage attempt dings the steward's own Honor."
  @spec sabotage_honor_penalty() :: pos_integer()
  def sabotage_honor_penalty, do: @sabotage_honor_penalty

  @doc "`honor - sabotage_honor_penalty/0` — the Honor consequence for provable sabotage."
  @spec apply_sabotage_penalty(integer()) :: integer()
  def apply_sabotage_penalty(honor), do: honor - @sabotage_honor_penalty

  @doc "Builds the attrs map for a fresh `StewardLog` insert — the one shape every steward action's own audit row shares."
  @spec log_attrs(
          term(),
          player_id(),
          player_id(),
          StewardLog.action(),
          map(),
          non_neg_integer(),
          boolean()
        ) :: map()
  def log_attrs(
        world_id,
        steward_player_id,
        owner_player_id,
        action,
        details,
        turn,
        sabotage? \\ false
      ) do
    %{
      world_id: world_id,
      steward_player_id: steward_player_id,
      owner_player_id: owner_player_id,
      action: action,
      details: details,
      turn: turn,
      sabotage: sabotage?
    }
  end
end
