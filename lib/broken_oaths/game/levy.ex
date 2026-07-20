defmodule BrokenOaths.Game.Levy do
  @moduledoc """
  A call-to-arms pledge record (story 908): the lord calls a vassal to
  send a share of their standing army to a war, for the war's duration.

  There is no formal `War` entity yet — the war is identified by its
  `target_player`, the rival the lord is fighting. `pledged_share` is
  the fraction (0, 1] of the vassal's standing army committed; the
  vassal keeps command of the pledged units.

  `status` tracks the call's lifecycle: `:pending` (issued, awaiting
  the vassal's response), `:answered` (units sent), `:refused` (the
  vassal declined — or, per the war-duration binding, pulled out
  early; `BrokenOaths.Game.Tribute` is where a mid-war withdrawal gets
  reclassified to `:refused` and Oath Strain/Honor react — this schema
  only carries the resulting state).

  ## Call-to-arms orchestration (pragdave decomposition, slice 6)

  `issue/5`, `answer/3`, and `refuse/3` are the state-taking "domain
  model" home (`.code_my_spec/knowledge/genserver_decomposition.md`)
  for the command logic `BrokenOaths.Game.WorldServer` used to bury
  inline as private `do_*` functions: each takes the WorldServer's own
  tick-`state` plus plain args and returns either a plain ok/error
  tuple or one that also carries an updated `state` — no `GenServer`,
  no `handle_*`, no process awareness. Every changeset these three
  build against a fresh or existing `Levy` row is still
  `BrokenOaths.Game.Tribute`'s own (`issue_changeset/5`,
  `answer_changeset/1`, `refuse_changeset/1`) — this module orchestrates
  WHO may call/answer/refuse and WHEN, `Tribute` still decides what the
  resulting row (and, on refusal, the paired Oath Strain/Honor
  consequence) actually looks like. `status_for/3` is the shared read
  both the lord's own `format_vassal/2` row and the vassal's own
  `vassal_status/2` badge call — the vassal has exactly one lord at a
  time, so at most one levy history exists between the two of them; the
  most recent (highest id) is "the" levy either side reads.
  `WorldServer`'s own `:issue_levy`/`:answer_levy`/`:refuse_levy`
  `handle_call` clauses are thin delegations into this section.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Game.Tribute
  alias BrokenOaths.Game.Vassalage
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.World

  @type status :: :pending | :answered | :refused

  @type t :: %__MODULE__{
          id: integer() | nil,
          pledged_share: float() | nil,
          status: status(),
          world_id: integer() | nil,
          lord_player_id: integer() | nil,
          vassal_player_id: integer() | nil,
          target_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          lord_player: Player.t() | Ecto.Association.NotLoaded.t(),
          vassal_player: Player.t() | Ecto.Association.NotLoaded.t(),
          target_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_levies" do
    field :pledged_share, :float
    field :status, Ecto.Enum, values: [:pending, :answered, :refused], default: :pending

    belongs_to :world, World
    belongs_to :lord_player, Player
    belongs_to :vassal_player, Player
    belongs_to :target_player, Player

    timestamps()
  end

  @doc false
  def changeset(levy, attrs) do
    levy
    |> cast(attrs, [
      :world_id,
      :lord_player_id,
      :vassal_player_id,
      :target_player_id,
      :pledged_share,
      :status
    ])
    |> validate_required([
      :world_id,
      :lord_player_id,
      :vassal_player_id,
      :target_player_id,
      :pledged_share,
      :status
    ])
    |> validate_number(:pledged_share, greater_than: 0, less_than_or_equal_to: 1)
    |> validate_lord_and_vassal_distinct()
    |> validate_target_not_vassal()
    |> validate_target_not_lord()
    |> assoc_constraint(:world)
    |> assoc_constraint(:lord_player)
    |> assoc_constraint(:vassal_player)
    |> assoc_constraint(:target_player)
  end

  # A lord cannot call themselves to arms.
  defp validate_lord_and_vassal_distinct(changeset) do
    lord_id = get_field(changeset, :lord_player_id)
    vassal_id = get_field(changeset, :vassal_player_id)

    if is_nil(lord_id) or is_nil(vassal_id) or lord_id != vassal_id do
      changeset
    else
      add_error(changeset, :vassal_player_id, "can't be the same as the lord")
    end
  end

  # The war's target is a third party — a call to arms can't pledge the
  # vassal's army against themselves.
  defp validate_target_not_vassal(changeset) do
    vassal_id = get_field(changeset, :vassal_player_id)
    target_id = get_field(changeset, :target_player_id)

    if is_nil(vassal_id) or is_nil(target_id) or vassal_id != target_id do
      changeset
    else
      add_error(changeset, :target_player_id, "can't be the same as the vassal")
    end
  end

  # Nor against the lord who's issuing the call.
  defp validate_target_not_lord(changeset) do
    lord_id = get_field(changeset, :lord_player_id)
    target_id = get_field(changeset, :target_player_id)

    if is_nil(lord_id) or is_nil(target_id) or lord_id != target_id do
      changeset
    else
      add_error(changeset, :target_player_id, "can't be the same as the lord")
    end
  end

  # -------------------------------------------------------------------
  # Call-to-arms orchestration (pragdave decomposition, slice 6)
  # -------------------------------------------------------------------

  @doc "The lord's own call to arms — a fresh, `:pending` row against a third player, requiring an ACTIVE `Vassalage` between the lord and the vassal being called."
  @spec issue(map(), term(), term(), term(), float()) :: {:ok, t()} | {:error, atom()}
  def issue(state, user, vassal_user_id, target_user_id, share) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, target_player} <- fetch_player(state, target_user_id),
         {:ok, _vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      Tribute.issue_changeset(
        state.world.id,
        lord_player.id,
        vassal_player.id,
        target_player.id,
        share
      )
      |> Repo.insert()
    end
  end

  @doc "The vassal answering their own lord's pending call — they keep command of the pledged units; nothing about answering moves a single one."
  @spec answer(map(), term(), term()) :: {:ok, t()} | {:error, atom()}
  def answer(state, user, lord_user_id) do
    with {:ok, vassal_player} <- fetch_player(state, user.id),
         {:ok, lord_player} <- fetch_player(state, lord_user_id),
         {:ok, levy} <- fetch_pending_levy(state.world.id, lord_player.id, vassal_player.id) do
      Tribute.answer_changeset(levy) |> Repo.update()
    end
  end

  @doc """
  The refusal branch — marks the levy refused, spikes the vassal's own
  Oath Strain (`Tribute.spike_oath_strain/1`), AND dings their own
  Honor (`Tribute.apply_refusal_honor_penalty/1`, QA issue c0ec53ed —
  criterion 7678's "strain and Honor hits" was only half-wired before
  this fix), "a publicly-legible broken obligation." The Honor half
  lives on `state.players` (in-memory tick-state, NOT a Repo-backed
  changeset the way `Levy`/`Vassalage` are) — the caller persists the
  returned `state` via `persist_tick/2`, the same shape a
  sabotage-penalty write and `apply_garrison_fate_honor/2` already
  establish for an in-place Honor-only state change.
  """
  @spec refuse(map(), term(), term()) :: {:ok, t(), map()} | {:error, atom()}
  def refuse(state, user, lord_user_id) do
    with {:ok, vassal_player} <- fetch_player(state, user.id),
         {:ok, lord_player} <- fetch_player(state, lord_user_id),
         {:ok, levy} <- fetch_pending_levy(state.world.id, lord_player.id, vassal_player.id),
         {:ok, refused} <- Tribute.refuse_changeset(levy) |> Repo.update(),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id),
         {:ok, _vassalage} <- Tribute.spike_oath_strain(vassalage) |> Repo.update() do
      new_state =
        update_in(state.players[vassal_player.id].honor, &Tribute.apply_refusal_honor_penalty/1)

      {:ok, refused, new_state}
    end
  end

  @doc "The most recent (highest id) levy between this exact lord/vassal pair — `nil` when none exists yet. Both `format_vassal/2` (the lord's own row) and `vassal_status/2` (the vassal's own badge) read this."
  @spec status_for(term(), term(), term()) :: status() | nil
  def status_for(world_id, lord_player_id, vassal_player_id) do
    __MODULE__
    |> where(
      [l],
      l.world_id == ^world_id and l.lord_player_id == ^lord_player_id and
        l.vassal_player_id == ^vassal_player_id
    )
    |> order_by([l], desc: l.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      levy -> levy.status
    end
  end

  defp fetch_pending_levy(world_id, lord_player_id, vassal_player_id) do
    __MODULE__
    |> where(
      [l],
      l.world_id == ^world_id and l.lord_player_id == ^lord_player_id and
        l.vassal_player_id == ^vassal_player_id and l.status == :pending
    )
    |> order_by([l], desc: l.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      levy -> {:ok, levy}
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

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer`, matching the sibling `BrokenOaths.Game.Unit`/
  # `BrokenOaths.Game.Cooperation`'s own "pure, process-unaware,
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
