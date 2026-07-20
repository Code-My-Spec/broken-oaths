defmodule BrokenOaths.Feudal.RebellionPact.Conspiracy do
  @moduledoc """
  Pure, process-unaware orchestration for the Pact of Broken Oaths
  (story 916) — the pragdave-pattern "domain model" home for the
  coordinated-rebellion logic `BrokenOaths.Simulation.WorldServer` used to
  bury inline (see `.code_my_spec/knowledge/genserver_decomposition.md`).

  Every function here takes the WorldServer's own tick-`state` (or the
  relevant substructure) plus plain args and returns either a reply
  tuple/value or an updated `state` — no `GenServer`, no `handle_*`, no
  process awareness. `WorldServer`'s own `handle_call`/tick clauses are
  thin one-line delegations into this module.

  Owns: opening/answering/informing on a pact chat, the masked pact
  view (criterion 7738: every OTHER member's own secret answer always
  reads "Outstanding"), the fellow-vassal candidate roster, the coarse
  conspiracy-heat gauge (criterion 7742), the lord's own defensive
  countermeasures (brace defenses / reposition / buy off conspirators),
  and the turn-boundary strike sweep — every `:committed` member of a
  pact whose `strike_turn` has arrived declares independence for real,
  through the SAME `BrokenOaths.Feudal.Rebellion.War.declare_independence/3`
  the immediate player-driven flow commits with.
  """

  import Ecto.Query

  alias BrokenOaths.Game
  alias BrokenOaths.Cities.City
  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Feudal.OathStrain
  alias BrokenOaths.Feudal.Rebellion.War
  alias BrokenOaths.Feudal.RebellionPact
  alias BrokenOaths.Feudal.RebellionPactMember
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.Feudal.Vassalage
  alias BrokenOaths.Repo
  alias BrokenOaths.Users

  # -------------------------------------------------------------------
  # Read-only, masked coordination state (criterion 7738)
  # -------------------------------------------------------------------

  @doc """
  `user`'s own membership in a `:forming` pact, masked per criterion
  7738: every OTHER member's own `status` always reads `:invited`
  ("Outstanding") no matter their real, secret answer — only the
  reader's own row (`own_status`) ever tells the truth. `nil` while
  `user` isn't currently a member of any `:forming` pact.
  """
  @spec pact_view(map(), map()) :: map() | nil
  def pact_view(state, user) do
    case find_player(state, user.id) do
      nil ->
        nil

      player ->
        case fetch_forming_pact_for_player(state.world.id, player.id) do
          nil -> nil
          pact -> format_pact_view(state, pact, player.id)
        end
    end
  end

  defp format_pact_view(state, pact, viewer_player_id) do
    own_member = Enum.find(pact.members, &(&1.player_id == viewer_player_id))

    members =
      for member <- pact.members do
        member_player = Map.fetch!(state.players, member.player_id)
        member_user = Users.get_user!(member_player.user_id)

        status =
          if member.player_id == viewer_player_id,
            do: member.commit_status,
            else: :invited

        %{user_id: member_user.id, email: member_user.email, status: status}
      end

    %{
      id: pact.id,
      strike_turn: pact.strike_turn,
      own_status: own_member.commit_status,
      informer?: own_member.informer,
      members: members
    }
  end

  defp fetch_forming_pact_for_player(world_id, player_id) do
    pact_id =
      from(m in RebellionPactMember,
        join: p in RebellionPact,
        on: p.id == m.rebellion_pact_id,
        where: m.player_id == ^player_id and p.world_id == ^world_id and p.status == :forming,
        select: p.id
      )
      |> Repo.one()

    case pact_id do
      nil -> nil
      id -> RebellionPact |> Repo.get!(id) |> Repo.preload(:members)
    end
  end

  @doc """
  Every FELLOW vassal of `user`'s own lord — `[]` for a free player, or
  a vassal with no fellow vassals under the same lord. Deliberately
  never excludes a fellow vassal already invited/committed elsewhere.
  """
  @spec pact_candidates(map(), map()) :: [map()]
  def pact_candidates(state, user) do
    with player when not is_nil(player) <- find_player(state, user.id),
         vassalage when not is_nil(vassalage) <- active_vassalage_for_vassal(state, player.id) do
      fellow_vassal_candidates(state, vassalage.lord_player_id, player.id)
    else
      nil -> []
    end
  end

  defp fellow_vassal_candidates(state, lord_player_id, exclude_player_id) do
    Vassalage
    |> where(
      [v],
      v.world_id == ^state.world.id and v.lord_player_id == ^lord_player_id and
        v.status == :active and v.vassal_player_id != ^exclude_player_id
    )
    |> Repo.all()
    |> Enum.map(&format_pact_candidate(state, &1))
  end

  defp format_pact_candidate(state, fellow) do
    fellow_player = Map.fetch!(state.players, fellow.vassal_player_id)
    fellow_user = Users.get_user!(fellow_player.user_id)
    %{user_id: fellow_user.id, email: fellow_user.email}
  end

  # -------------------------------------------------------------------
  # Pact chat (opening / answering / informing)
  # -------------------------------------------------------------------

  @doc """
  `strike_turn_param` arrives a positive integer of turn BOUNDARIES from
  right now (never an absolute world-turn number). Opener becomes a
  member of their own pact too (`:invited`, same as any real invitee); a
  non-fellow-vassal invitee is silently dropped rather than refusing
  the whole call.
  """
  @spec open_pact_chat(map(), map(), integer() | String.t(), [integer() | String.t()]) ::
          {:ok, RebellionPact.t()} | {:error, atom()}
  def open_pact_chat(state, user, strike_turn_param, invitee_user_ids) do
    with {:ok, opener_player} <- fetch_player(state, user.id),
         {:ok, vassalage} <- fetch_vassalage_as_vassal(state, opener_player.id),
         {:ok, offset} <- parse_strike_turn(strike_turn_param) do
      lord_player_id = vassalage.lord_player_id

      {:ok, pact} =
        %RebellionPact{}
        |> RebellionPact.changeset(%{
          world_id: state.world.id,
          lord_player_id: lord_player_id,
          opener_player_id: opener_player.id,
          strike_turn: state.turn + offset,
          status: :forming
        })
        |> Repo.insert()

      fellow_vassal_ids =
        Vassalage
        |> where(
          [v],
          v.world_id == ^state.world.id and v.lord_player_id == ^lord_player_id and
            v.status == :active
        )
        |> select([v], v.vassal_player_id)
        |> Repo.all()
        |> MapSet.new()

      invitee_player_ids =
        invitee_user_ids
        |> Enum.map(&parse_pact_id/1)
        |> Enum.map(&find_player(state, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.id)
        |> Enum.filter(&MapSet.member?(fellow_vassal_ids, &1))

      member_player_ids = Enum.uniq([opener_player.id | invitee_player_ids])

      for player_id <- member_player_ids do
        {:ok, _member} =
          %RebellionPactMember{}
          |> RebellionPactMember.changeset(%{
            rebellion_pact_id: pact.id,
            player_id: player_id,
            commit_status: :invited
          })
          |> Repo.insert()
      end

      {:ok, pact}
    end
  end

  defp parse_strike_turn(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_strike_turn(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_strike_turn}
    end
  end

  defp parse_strike_turn(_value), do: {:error, :invalid_strike_turn}

  defp parse_pact_id(id) when is_integer(id), do: id
  defp parse_pact_id(id) when is_binary(id), do: String.to_integer(id)

  @doc "Records `user`'s own secret `commit_status` (`:committed` or `:declined`) against their currently-forming pact."
  @spec pact_answer(map(), map(), RebellionPactMember.commit_status()) ::
          {:ok, RebellionPactMember.t()} | {:error, atom()}
  def pact_answer(state, user, commit_status) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, member} <- fetch_forming_pact_member(state.world.id, player.id) do
      RebellionPactMember.changeset(member, %{commit_status: commit_status}) |> Repo.update()
    end
  end

  @doc "Criterion 7741 — flips `informer: true` only, never `commit_status`: informing changes no odds."
  @spec pact_inform(map(), map()) :: {:ok, RebellionPactMember.t()} | {:error, atom()}
  def pact_inform(state, user) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, member} <- fetch_forming_pact_member(state.world.id, player.id) do
      RebellionPactMember.changeset(member, %{informer: true}) |> Repo.update()
    end
  end

  defp fetch_forming_pact_member(world_id, player_id) do
    RebellionPactMember
    |> join(:inner, [m], p in RebellionPact, on: p.id == m.rebellion_pact_id)
    |> where(
      [m, p],
      m.player_id == ^player_id and p.world_id == ^world_id and p.status == :forming
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_a_pact_member}
      member -> {:ok, member}
    end
  end

  # -------------------------------------------------------------------
  # Conspiracy heat (criterion 7742)
  # -------------------------------------------------------------------

  @doc "Criterion 7742 — the coarse aggregate `OathStrain.heat/1`, never the exact per-vassal figure."
  @spec conspiracy_heat(map(), map()) :: OathStrain.strain()
  def conspiracy_heat(state, user) do
    case find_player(state, user.id) do
      nil ->
        0

      player ->
        Vassalage
        |> where(
          [v],
          v.world_id == ^state.world.id and v.lord_player_id == ^player.id and v.status == :active
        )
        |> select([v], v.oath_strain)
        |> Repo.all()
        |> OathStrain.heat()
    end
  end

  # -------------------------------------------------------------------
  # Lord countermeasures
  # -------------------------------------------------------------------

  @doc """
  Immediate, targeted Repo write — heals every one of `user`'s own
  cities to full, bypassing the generic tick diff since a city's own HP
  is otherwise only ever mutated inside a tick.
  """
  @spec brace_defenses(map(), map()) :: {:ok, map()} | {:error, atom()}
  def brace_defenses(state, user) do
    with {:ok, player} <- fetch_player(state, user.id) do
      city_ids =
        state.cities
        |> Map.values()
        |> Enum.filter(&(&1.player_id == player.id))
        |> Enum.map(& &1.id)

      max_hp = CityDefense.max_hp()
      Repo.update_all(from(c in City, where: c.id in ^city_ids), set: [hp: max_hp])

      new_cities =
        Enum.reduce(city_ids, state.cities, fn id, acc ->
          Map.update!(acc, id, &%{&1 | hp: max_hp})
        end)

      {:ok, %{state | cities: new_cities}}
    end
  end

  @doc "Heals `user`'s own Lord unit to full — the lord's own defensive countermeasure."
  @spec reposition_lord(map(), map()) :: {:ok, map()} | {:error, atom()}
  def reposition_lord(state, user) do
    with {:ok, player} <- fetch_player(state, user.id),
         lord_unit when not is_nil(lord_unit) <- find_lord_unit(state, player.id) do
      max_hp = lord_unit.max_hp
      Repo.update_all(from(u in Unit, where: u.id == ^lord_unit.id), set: [hp: max_hp])
      new_units = Map.put(state.units, lord_unit.id, %{lord_unit | hp: max_hp})
      {:ok, %{state | units: new_units}}
    else
      nil -> {:error, :no_lord_unit}
      error -> error
    end
  end

  defp find_lord_unit(state, player_id) do
    state.units
    |> Map.values()
    |> Enum.find(&(&1.type == :lord and &1.player_id == player_id))
  end

  @doc """
  A broad concession a warned lord can make without knowing WHICH of
  their own vassals is actually plotting — the roster stays secret even
  once informed (criterion 7741).
  """
  @spec buy_off_conspirators(map(), map()) :: :ok | {:error, atom()}
  def buy_off_conspirators(state, user) do
    with {:ok, player} <- fetch_player(state, user.id) do
      Vassalage
      |> where(
        [v],
        v.world_id == ^state.world.id and v.lord_player_id == ^player.id and v.status == :active
      )
      |> Repo.all()
      |> Enum.each(fn vassalage ->
        new_strain = OathStrain.ease_gift(vassalage.oath_strain)
        Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
      end)

      :ok
    end
  end

  # -------------------------------------------------------------------
  # Turn-boundary strike sweep
  # -------------------------------------------------------------------

  @doc """
  Criterion 7739 — the tick-boundary phase: every `:forming` pact whose
  `strike_turn` has arrived (`<=`, not `==`, the same catch-up-safe
  comparison the rebellion end-condition checks already use elsewhere)
  reveals and fires all at once. Every `:committed` member declares
  independence for real, through the SAME
  `BrokenOaths.Feudal.Rebellion.War.declare_independence/3` the immediate
  player-driven `"declare_independence"` event commits with — no
  coordination bonus, each conspirator resolves their own reputation-
  driven rising and their own strain-sized army independently. A member
  who never committed (still `:invited`, or `:declined`) is left
  completely untouched.
  """
  @spec apply_rebellion_pact_strikes(map()) :: map()
  def apply_rebellion_pact_strikes(state) do
    if Game.feudal_enabled?() do
      RebellionPact
      |> where(
        [p],
        p.world_id == ^state.world.id and p.status == :forming and p.strike_turn <= ^state.turn
      )
      |> Repo.all()
      |> Repo.preload(:members)
      |> Enum.reduce(state, &strike_pact/2)
    else
      state
    end
  end

  defp strike_pact(pact, state) do
    {:ok, _struck} = RebellionPact.changeset(pact, %{status: :struck}) |> Repo.update()

    pact.members
    |> Enum.filter(&RebellionPactMember.committed?/1)
    |> Enum.reduce(state, &strike_member(&1, pact, &2))
  end

  defp strike_member(member, pact, state) do
    with {:ok, vassal_player} <- Map.fetch(state.players, member.player_id),
         {:ok, lord_player} <- Map.fetch(state.players, pact.lord_player_id),
         {:ok, _result, new_state, _lord_events} <-
           War.declare_independence(state, %{id: vassal_player.user_id}, lord_player.user_id) do
      new_state
    else
      _ -> state
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

  defp active_vassalage_for_vassal(state, vassal_player_id) do
    Repo.get_by(Vassalage,
      world_id: state.world.id,
      vassal_player_id: vassal_player_id,
      status: :active
    )
  end

  defp fetch_vassalage_as_vassal(state, vassal_player_id) do
    case active_vassalage_for_vassal(state, vassal_player_id) do
      nil -> {:error, :not_a_vassal}
      vassalage -> {:ok, vassalage}
    end
  end
end
