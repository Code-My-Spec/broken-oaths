defmodule BrokenOaths.Game.Tribute do
  @moduledoc """
  Per-turn gold tribute and call-to-arms levy business rules (story
  908), built on top of `BrokenOaths.Game.Vassalage` and
  `BrokenOaths.Game.Levy` — mirrors `BrokenOaths.Game.Cooperation`'s own
  "pure math/changesets, no `Repo`" role: `BrokenOaths.Game.WorldServer`
  is the imperative shell that reads every active vassalage out of the
  DB once per turn boundary, calls `collect_all/5`, and persists the
  gold/`BrokenOaths.Game.GoldLog` result — plus the immediate
  issue/answer/refuse levy events, resolved the same way `Alliance`
  propose/accept already is (persisted immediately, no turn boundary
  required).

  ## Gold tribute

  `tribute = vassal's gross per-turn gold income × the lord's own
  tribute_rate` (rounded to the nearest gold), transferred vassal→lord
  every turn boundary — never capped by the vassal's own treasury
  balance: `tribute_amount/2` computes the same figure regardless of
  what the vassal can actually afford, so a vassal with too little gold
  goes into DEBT (a negative balance), not a partial payment
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-5
  decisions": "accrues; negative balance allowed; NO auto-penalty").
  Zero or negative income skims nothing that turn — "the lord simply
  goes unpaid," never a debit that could somehow overshoot.

  Story 912 shipped the real per-turn city gold YIELD this module's
  own gap used to document: `BrokenOaths.Cities.Yields.city_gold_income/2`
  (a per-size base plus worked-Coast-tile gold, recomputed fresh every
  boundary) — `collect_all/5`'s own `income_by_player` argument is now
  supplied by `BrokenOaths.Game.WorldServer`'s `apply_tribute/1`,
  summing that REAL figure over every city a vassal owns
  (`gold_income_by_player/1`), not the test-only
  `:set_player_gold_income_for_test` seam this module used to be the
  only reader of (that seam still exists for narrower test scenarios,
  but no longer feeds this phase at all).

  ## Call to arms

  `issue_changeset/5` builds a fresh `Levy` (`:pending`) against a
  THIRD player (the schema's own `validate_target_not_vassal`/
  `validate_target_not_lord` guards already refuse the lord or the
  vassal themselves as a target). `answer_changeset/1` commits the
  vassal's own pledge (`:answered`) — they keep command of the pledged
  units; nothing about answering moves any unit itself, only the
  record. `refuse_changeset/1` marks it `:refused`; `spike_oath_strain/1`
  and `apply_refusal_honor_penalty/1` are the PAIRED consequences a
  refusal (or, per the design doc, a mid-war withdrawal reclassified to
  refusal) always carries — Oath Strain rises by
  `oath_strain_refusal_spike/0`, clamped at 100, AND Honor drops by
  `refusal_honor_penalty/0` (QA issue c0ec53ed — criterion 7678's
  "takes strain and Honor hits" was only half-wired: Oath Strain rose,
  Honor never moved. `refusal_honor_penalty/0` mirrors the sibling
  execute-garrison penalty's own unclamped `honor - N` shape,
  `Siege.apply_execute_honor_penalty/1`).

  ## The tribute rate lever

  `set_rate_changeset/2` is the lord-set, per-vassal, adjustable dial
  the design doc pulls into this foundation story ("Round-4 final
  foundation mechanics") — a plain `Vassalage.tribute_rate` update that
  takes effect on the vassal's NEXT turn boundary tribute, same as any
  other in-place field commit (`BrokenOaths.Game.rename_city/4`'s own
  "persists immediately, no turn boundary required" status).
  """

  alias BrokenOaths.Game.Levy
  alias BrokenOaths.Game.OathStrain
  alias BrokenOaths.Game.Vassalage

  @type player_id :: term()
  @type players :: %{player_id() => %{gold: integer()}}
  @type gold_log_attrs :: %{
          world_id: term(),
          from_player_id: player_id(),
          to_player_id: player_id(),
          turn: non_neg_integer(),
          amount: pos_integer(),
          reason: :tribute
        }

  @oath_strain_refusal_spike 15
  @max_oath_strain 100
  @refusal_honor_penalty 3

  # -------------------------------------------------------------------
  # Gold tribute
  # -------------------------------------------------------------------

  @doc "How much Oath Strain a refused (or withdrawn) call to arms spikes, before the 0-100 clamp."
  @spec oath_strain_refusal_spike() :: pos_integer()
  def oath_strain_refusal_spike, do: @oath_strain_refusal_spike

  @doc """
  `income × rate`, rounded to the nearest gold — `0` for a non-positive
  income (never a negative tribute).
  """
  @spec tribute_amount(integer(), float()) :: non_neg_integer()
  def tribute_amount(income, _rate) when income <= 0, do: 0
  def tribute_amount(income, rate), do: round(income * rate)

  @doc """
  Move `vassalage`'s own tribute out of its vassal's treasury and into
  its lord's, allowing the vassal's own balance to go negative — returns
  the updated `players` map and the amount actually moved (`0` if the
  vassal's income this turn was non-positive, in which case `players`
  is returned untouched).
  """
  @spec collect(players(), Vassalage.t(), integer()) :: {players(), non_neg_integer()}
  def collect(players, vassalage, income) do
    case tribute_amount(income, vassalage.tribute_rate) do
      0 ->
        {players, 0}

      tribute ->
        players =
          players
          |> update_in([vassalage.vassal_player_id, :gold], &(&1 - tribute))
          |> update_in([vassalage.lord_player_id, :gold], &(&1 + tribute))

        {players, tribute}
    end
  end

  @doc """
  Resolve every ACTIVE vassalage in `vassalages` against `players` for
  a single turn boundary — scales to many concurrent relationships per
  world, each resolved independently within the same pass. Returns the
  updated `players` map plus one `GoldLog`-shaped attrs map per
  vassalage that actually paid (an income-less vassal contributes no
  log entry, not a zero-amount one).
  """
  @spec collect_all([Vassalage.t()], players(), %{player_id() => integer()}, term(), non_neg_integer()) ::
          {players(), [gold_log_attrs()]}
  def collect_all(vassalages, players, income_by_player, world_id, turn) do
    vassalages
    |> Enum.filter(&(&1.status == :active))
    |> Enum.reduce({players, []}, fn vassalage, {players_acc, logs_acc} ->
      income = Map.get(income_by_player, vassalage.vassal_player_id, 0)

      case collect(players_acc, vassalage, income) do
        {new_players, 0} ->
          {new_players, logs_acc}

        {new_players, tribute} ->
          log = %{
            world_id: world_id,
            from_player_id: vassalage.vassal_player_id,
            to_player_id: vassalage.lord_player_id,
            turn: turn,
            amount: tribute,
            reason: :tribute
          }

          {new_players, [log | logs_acc]}
      end
    end)
    |> then(fn {players_acc, logs_acc} -> {players_acc, Enum.reverse(logs_acc)} end)
  end

  # -------------------------------------------------------------------
  # The tribute rate lever
  # -------------------------------------------------------------------

  @doc "Build the changeset for the lord raising/lowering `vassalage`'s own tribute rate."
  @spec set_rate_changeset(Vassalage.t(), float()) :: Ecto.Changeset.t()
  def set_rate_changeset(vassalage, rate), do: Vassalage.changeset(vassalage, %{tribute_rate: rate})

  # -------------------------------------------------------------------
  # Call to arms
  # -------------------------------------------------------------------

  @doc "Build the changeset issuing a fresh, `:pending` call to arms against a third player."
  @spec issue_changeset(term(), player_id(), player_id(), player_id(), float()) ::
          Ecto.Changeset.t()
  def issue_changeset(world_id, lord_player_id, vassal_player_id, target_player_id, share) do
    Levy.changeset(%Levy{}, %{
      world_id: world_id,
      lord_player_id: lord_player_id,
      vassal_player_id: vassal_player_id,
      target_player_id: target_player_id,
      pledged_share: share,
      status: :pending
    })
  end

  @doc "Build the changeset answering a pending call to arms — the vassal keeps command of the pledged units."
  @spec answer_changeset(Levy.t()) :: Ecto.Changeset.t()
  def answer_changeset(levy), do: Levy.changeset(levy, %{status: :answered})

  @doc "Build the changeset refusing (or withdrawing from) a call to arms — pair with `spike_oath_strain/1` AND `apply_refusal_honor_penalty/1`."
  @spec refuse_changeset(Levy.t()) :: Ecto.Changeset.t()
  def refuse_changeset(levy), do: Levy.changeset(levy, %{status: :refused})

  @doc """
  Build the changeset spiking `vassalage`'s own Oath Strain by
  `oath_strain_refusal_spike/0`, clamped at `#{@max_oath_strain}` — the
  refused-call consequence: "Refusal spikes Oath Strain and dings the
  Honor ledger" — see `refusal_honor_penalty/0`/`apply_refusal_honor_penalty/1`
  below for the Honor half of that pair (QA issue c0ec53ed). Story 913:
  delegates its magnitude to `OathStrain.spike_refused_levy/1` — the
  now-canonical home for this number (`OathStrain`'s own moduledoc) —
  rather than carrying a second copy that could drift out of sync;
  `oath_strain_refusal_spike/0` stays as this module's own public
  accessor (unchanged value, `refusal_honor_penalty/0`'s sibling), only
  the WRITE path underneath it changed.
  """
  @spec spike_oath_strain(Vassalage.t()) :: Ecto.Changeset.t()
  def spike_oath_strain(vassalage) do
    new_strain = OathStrain.spike_refused_levy(vassalage.oath_strain)
    Vassalage.changeset(vassalage, %{oath_strain: new_strain})
  end

  # -------------------------------------------------------------------
  # Refusal Honor consequence (QA issue c0ec53ed)
  # -------------------------------------------------------------------

  @doc """
  How much Honor a refused (or withdrawn) call to arms costs — criterion
  7678's "takes strain and Honor hits," the Honor half of the pair
  alongside `oath_strain_refusal_spike/0`. Deliberately calibrated
  against the sibling garrison-execute penalty
  (`Siege.execute_garrison_honor_penalty/0`, `2`) — refusing an oath is
  a step worse than executing a beaten garrison, so this reads
  slightly higher.
  """
  @spec refusal_honor_penalty() :: pos_integer()
  def refusal_honor_penalty, do: @refusal_honor_penalty

  @doc "`honor - refusal_honor_penalty/0` — the Honor consequence for refusing (or withdrawing from) a call to arms, unclamped (mirrors `Siege.apply_execute_honor_penalty/1`)."
  @spec apply_refusal_honor_penalty(integer()) :: integer()
  def apply_refusal_honor_penalty(honor), do: honor - @refusal_honor_penalty
end
