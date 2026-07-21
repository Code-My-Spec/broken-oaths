defmodule BrokenOaths.Feudal.Bank do
  @moduledoc """
  Gold-bank core for story 909: pure business rules on top of the
  `banked_gold`/`bank_cap` fields living directly on `BrokenOaths.Game.
  Player` (migration `20260718130000`) — mirrors `BrokenOaths.Game.
  Tribute`'s own "pure math, no `Repo`" role, plus (pragdave
  decomposition, slice 6 — `.code_my_spec/knowledge/genserver_decomposition.md`)
  the state-taking orchestration `BrokenOaths.Simulation.WorldServer` used to
  bury inline as private `do_*` functions: `status_for/2`, `collect_for/2`,
  `upgrade_for/2`, and `apply_income/3` each take the WorldServer's own
  tick-`state` (or the relevant substructure) plus plain args and return
  either a plain value or an updated map — no `GenServer`, no
  `handle_*`, no process awareness. `WorldServer`'s own
  `:bank`/`:collect_bank`/`:upgrade_bank` `handle_call` clauses, and its
  own `apply_bank/1` tick phase, are thin delegations into this module.

  ## Logged in vs. offline

  `settle_income/3` is the whole turn-tick contract: a LOGGED IN
  player's income flows straight to their usable treasury (`gold`); an
  OFFLINE player's income accrues into their own capped bank
  (`banked_gold`, `bank_cap`) instead, via `accrue/3`. Once the bank is
  FULL, further offline income is simply wasted — never lost from
  `gold` (nothing was ever there to lose), never negative, and never
  carried over once the player logs back in and collects: the point is
  "return or be tended," not "bank forever." A non-positive income
  moves nothing either way (mirrors `Tribute.tribute_amount/2`'s own
  "zero or negative income skims nothing" rule). `apply_income/3` is the
  turn-boundary sweep over every player who earned income this turn:
  it resolves each one's own `Presence.online?/2` fact and calls
  `settle_income/3` — `WorldServer.gold_income_by_player/1`'s own return
  stays owned there since `BrokenOaths.Feudal.Tribute`'s own tribute phase
  reads the SAME figure; only the settle-and-write iteration moves here.

  ## Collect and upgrade

  `collect/1` is the deliberate engagement tap: sweep the ENTIRE bank
  into the treasury in one motion, emptying it — the same math
  `BrokenOaths.Feudal.Stewardship`'s own bank-sweep action reuses
  (`steward_collect/1`, an alias kept separate only so each call site
  documents its own actor). `upgrade/1` is the real economy decision:
  raise the cap for a gold cost, refused outright (no partial charge)
  when the player can't afford it. `collect_for/2` and `upgrade_for/2`
  are the immediate, `state`-taking commands behind `WorldServer`'s own
  `:collect_bank`/`:upgrade_bank` — both gated on `Game.feudal_enabled?/0`
  the same belt-and-suspenders way `apply_income/3`'s own caller already
  is.

  ## Upkeep and disband-when-broke (stories 922/923)

  `apply_upkeep/2` is the SWEEP `WorldServer.run_tick/1`'s own
  `apply_bank/1` phase now calls instead of `apply_income/3` directly —
  it nets every player's own gross city income against their own
  maintenance bill (`maintenance_by_player/1`: every owned unit's
  `BrokenOaths.Units.Maintenance.upkeep/1` plus every owned city's
  `BrokenOaths.Cities.Buildings.city_upkeep/1`), then settles the NET
  figure. A surplus (net >= 0) is handed straight to `apply_income/3`
  UNCHANGED — the exact same function, called with a net rather than a
  gross figure, so a world with no upkeep-bearing units/buildings (net
  always equals gross) ticks identically to before this story. A deficit
  is a new path (`settle_deficit/4`): paid out of the TREASURY regardless
  of online status (`player.gold + net`, `net` negative) — a shortfall is
  never the offline "not around to collect" case `settle_income/3`'s own
  `false` branch models, so it never touches `banked_gold`. Clamped at
  `0` when the treasury itself can't cover it, and that clamp is exactly
  the BROKE signal that triggers `disband_broke/2`: one unit gone this
  tick, freeing up next turn's upkeep, same "shed units until you can
  afford your army" consequence Civ 6 itself has.
  """

  alias BrokenOaths.Cities.Buildings
  alias BrokenOaths.Game
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Players.Presence
  alias BrokenOaths.Units.Maintenance
  alias BrokenOaths.Worlds.World

  @type player :: %{gold: integer(), banked_gold: integer(), bank_cap: integer()}
  @type alert_event :: {:city_alert, term(), String.t()}

  # Story 923's disband-victim ordering: military over civilian, the
  # Lord never eligible at all (filtered before this split — see
  # `disband_target/2`). `:barbarian_warrior` never appears here; a
  # barbarian carries no `player_id`, so it's never among `owned`.
  @military_disband_types [:warrior, :bronze_spearman, :archer, :galley]
  @civilian_disband_types [:settler, :worker]

  @starting_cap 100
  @cap_increment 100
  @upgrade_cost_multiplier 5

  @doc "The bank's own starting capacity for a freshly-joined player — mirrors `Player`'s own `bank_cap` schema default."
  @spec starting_cap() :: pos_integer()
  def starting_cap, do: @starting_cap

  @doc "Gold cost to raise `cap` to `upgraded_cap/1`'s own next tier."
  @spec upgrade_cost(pos_integer()) :: pos_integer()
  def upgrade_cost(cap), do: cap * @upgrade_cost_multiplier

  @doc "The cap a successful `upgrade/1` raises `cap` to."
  @spec upgraded_cap(pos_integer()) :: pos_integer()
  def upgraded_cap(cap), do: cap + @cap_increment

  @doc """
  `banked + income`, clamped at `cap` — a non-positive `income` leaves
  `banked` untouched (never a negative accrual).
  """
  @spec accrue(non_neg_integer(), pos_integer(), integer()) :: non_neg_integer()
  def accrue(banked, _cap, income) when income <= 0, do: banked
  def accrue(banked, cap, income), do: min(banked + income, cap)

  @doc """
  Resolve one player's own turn-boundary income: straight to `:gold`
  while `online?`, into the capped `:banked_gold` otherwise. A
  non-positive `income` is a no-op either way.
  """
  @spec settle_income(player(), integer(), boolean()) :: player()
  def settle_income(player, income, _online?) when income <= 0, do: player

  def settle_income(player, income, true), do: %{player | gold: player.gold + income}

  def settle_income(player, income, false),
    do: %{player | banked_gold: accrue(player.banked_gold, player.bank_cap, income)}

  @doc "Sweep the entire bank into the treasury, emptying it — returns `{new_player, amount_swept}`."
  @spec collect(player()) :: {player(), non_neg_integer()}
  def collect(player) do
    swept = player.banked_gold
    {%{player | gold: player.gold + swept, banked_gold: 0}, swept}
  end

  @doc """
  A steward's own bank sweep on the offline owner's behalf — IDENTICAL
  math to `collect/1` (pure stewardship: every gold lands with the
  owner, the steward's own treasury never moves), kept as its own named
  function so `BrokenOaths.Feudal.Stewardship`'s call site documents
  itself without reaching into `collect/1` under a name that implies
  the OWNER's own click.
  """
  @spec steward_collect(player()) :: {player(), non_neg_integer()}
  def steward_collect(player), do: collect(player)

  @doc """
  Raise `player`'s own bank cap for `upgrade_cost/1`'s own gold price —
  refused, with `player` returned untouched, when they can't afford it
  (no partial charge).
  """
  @spec upgrade(player()) :: {:ok, player()} | {:error, :insufficient_gold}
  def upgrade(%{gold: gold, bank_cap: cap} = player) do
    cost = upgrade_cost(cap)

    if gold >= cost do
      {:ok, %{player | gold: gold - cost, bank_cap: upgraded_cap(cap)}}
    else
      {:error, :insufficient_gold}
    end
  end

  @doc "`player.gold >= upgrade_cost(player.bank_cap)` — the same affordability check `upgrade/1` itself makes, exposed for a caller that wants to know without attempting the charge."
  @spec can_afford_upgrade?(player()) :: boolean()
  def can_afford_upgrade?(%{gold: gold, bank_cap: cap}), do: gold >= upgrade_cost(cap)

  @doc "`%Player{}`-shaped bank status, `%{gold:, cap:}` — the pair `GameLive.BankPanel` renders as `bank-gold`/`bank-cap`."
  @spec status(Player.t() | player()) :: %{gold: non_neg_integer(), cap: pos_integer()}
  def status(%{banked_gold: banked, bank_cap: cap}), do: %{gold: banked, cap: cap}

  # -------------------------------------------------------------------
  # State-taking orchestration (pragdave decomposition, slice 6)
  # -------------------------------------------------------------------

  @doc "`user`'s own `status/1`, or the freshly-joined default (`starting_cap/0`, zero banked) for a user who hasn't joined this world at all."
  @spec status_for(map(), term()) :: %{gold: non_neg_integer(), cap: pos_integer()}
  def status_for(state, user) do
    case find_player(state, user.id) do
      nil -> %{gold: 0, cap: starting_cap()}
      player -> status(player)
    end
  end

  @doc "The immediate command behind `WorldServer`'s own `:collect_bank` — `collect/1` against `user`'s own player, refused while `Game.feudal_enabled?/0` reads `false`."
  @spec collect_for(map(), term()) :: {:ok, map()} | {:error, atom()}
  def collect_for(state, user) do
    with :ok <- ensure_feudal_enabled(),
         {:ok, player} <- fetch_player(state, user.id) do
      {new_player, _swept} = collect(player)
      {:ok, %{state | players: Map.put(state.players, player.id, new_player)}}
    end
  end

  @doc "The immediate command behind `WorldServer`'s own `:upgrade_bank` — `upgrade/1` against `user`'s own player, refused while `Game.feudal_enabled?/0` reads `false` (before `upgrade/1`'s own affordability check even runs)."
  @spec upgrade_for(map(), term()) :: {:ok, map()} | {:error, atom()}
  def upgrade_for(state, user) do
    with :ok <- ensure_feudal_enabled(),
         {:ok, player} <- fetch_player(state, user.id),
         {:ok, upgraded} <- upgrade(player) do
      {:ok, %{state | players: Map.put(state.players, player.id, upgraded)}}
    end
  end

  @doc """
  Turn-boundary settlement for every player who earned income this
  turn: resolves each one's own `Presence.online?/2` fact and calls
  `settle_income/3` — straight to `:gold` while online, into the capped
  `:banked_gold` otherwise. A player id present in `income_by_player`
  but missing from `players` (owns no `Player` row at all — shouldn't
  happen, but `WorldServer.gold_income_by_player/1` never checks) is
  silently skipped, same "missing means untouched" contract every other
  in-tick diff keeps.
  """
  @spec apply_income(%{term() => player()}, %{term() => integer()}, World.t()) ::
          %{term() => player()}
  def apply_income(players, income_by_player, world) do
    Enum.reduce(income_by_player, players, &settle_player_income(&1, &2, world))
  end

  defp settle_player_income({player_id, income}, players, world) do
    case Map.get(players, player_id) do
      nil ->
        players

      player ->
        online? = Presence.online?(world, %{id: player.user_id})
        Map.put(players, player_id, settle_income(player, income, online?))
    end
  end

  # -------------------------------------------------------------------
  # Upkeep and disband-when-broke (stories 922/923) — see this module's
  # own moduledoc "Upkeep and disband-when-broke" section.
  # -------------------------------------------------------------------

  @doc """
  Every player's own total gold upkeep this turn: every unit they own
  (`Maintenance.upkeep/1`) plus every city they own
  (`Buildings.city_upkeep/1`), grouped by `player_id` and summed. A unit
  with no owner (`:barbarian_warrior`, `player_id: nil`) is filtered out
  first — nobody ever owes for a unit nobody owns. Public (unlike
  `WorldServer.gold_income_by_player/1`, its sibling on the income side)
  because `WorldServer`'s own `:gold_per_turn` read needs the SAME figure
  `apply_upkeep/2` settles with, outside any tick.
  """
  @spec maintenance_by_player(map()) :: %{term() => non_neg_integer()}
  def maintenance_by_player(state) do
    unit_upkeep = sum_by_owner(state.units, &Maintenance.upkeep/1)
    building_upkeep = sum_by_owner(state.cities, &Buildings.city_upkeep/1)
    Map.merge(unit_upkeep, building_upkeep, fn _player_id, u, b -> u + b end)
  end

  defp sum_by_owner(entities, upkeep_fun) do
    entities
    |> Map.values()
    |> Enum.filter(&(&1.player_id != nil))
    |> Enum.group_by(& &1.player_id)
    |> Map.new(fn {player_id, owned} -> {player_id, owned |> Enum.map(upkeep_fun) |> Enum.sum()} end)
  end

  @doc """
  The turn-boundary NET settlement `WorldServer.apply_bank/1` calls
  instead of `apply_income/3` directly (see this module's own moduledoc)
  — nets `income_by_player` (gross, `WorldServer.gold_income_by_player/1`)
  against `maintenance_by_player/1`, hands every player with a surplus
  (net >= 0, INCLUDING a player who owes nothing at all) to `apply_income/3`
  unchanged, and settles every deficit via `settle_deficit/4`, disbanding
  a unit for whichever players that clamps to broke. Returns
  `{new_state, alert_events}` — `alert_events` the same `{:city_alert,
  user_id, message}` shape `WorldServer`'s own `approach_alert_events/2`
  already pushes, one per player who lost a unit this tick, for
  `run_tick/1`'s own end-of-tick broadcast to fold in alongside every
  other tick alert.
  """
  @spec apply_upkeep(map(), %{term() => integer()}) :: {map(), [alert_event()]}
  def apply_upkeep(state, income_by_player) do
    maintenance_by_player = maintenance_by_player(state)

    net_by_player =
      (Map.keys(income_by_player) ++ Map.keys(maintenance_by_player))
      |> Enum.uniq()
      |> Map.new(fn player_id ->
        net = Map.get(income_by_player, player_id, 0) - Map.get(maintenance_by_player, player_id, 0)
        {player_id, net}
      end)

    {surplus, deficit} = Enum.split_with(net_by_player, fn {_id, net} -> net >= 0 end)

    state = %{state | players: apply_income(state.players, Map.new(surplus), state.world)}

    Enum.reduce(deficit, {state, []}, fn {player_id, net}, {acc_state, alerts} ->
      settle_deficit(acc_state, player_id, net, alerts)
    end)
  end

  # A deficit is paid from the TREASURY regardless of online status —
  # see this module's own moduledoc for why it never touches
  # `banked_gold`. A player id missing from `players` is skipped, same
  # "missing means untouched" contract `settle_player_income/3` keeps.
  defp settle_deficit(state, player_id, net, alerts) do
    case Map.get(state.players, player_id) do
      nil ->
        {state, alerts}

      player ->
        paid_gold = player.gold + net

        if paid_gold >= 0 do
          new_player = %{player | gold: paid_gold}
          {%{state | players: Map.put(state.players, player_id, new_player)}, alerts}
        else
          broke_player = %{player | gold: 0}
          state = %{state | players: Map.put(state.players, player_id, broke_player)}
          disband_broke(state, broke_player, alerts)
        end
    end
  end

  # One unit, this tick, for `player` — the NEWEST (highest id),
  # non-Lord unit, preferring military over civilian
  # (`disband_target/2`). No eligible unit (only a Lord, or nothing at
  # all) leaves the player clamped at 0 with no further consequence —
  # losing the Lord would wrongly trigger the heir mechanic, so it's
  # never a candidate.
  defp disband_broke(state, player, alerts) do
    case disband_target(state, player.id) do
      nil ->
        {state, alerts}

      {unit_id, unit} ->
        new_state = %{state | units: Map.delete(state.units, unit_id)}
        message = "Couldn't pay upkeep — disbanded your #{unit_label(unit.type)}."
        {new_state, [{:city_alert, player.user_id, message} | alerts]}
    end
  end

  defp disband_target(state, player_id) do
    owned =
      for {id, unit} <- state.units,
          unit.player_id == player_id,
          unit.type != :lord,
          do: {id, unit}

    military = Enum.filter(owned, fn {_id, u} -> u.type in @military_disband_types end)
    civilian = Enum.filter(owned, fn {_id, u} -> u.type in @civilian_disband_types end)

    cond do
      military != [] -> newest(military)
      civilian != [] -> newest(civilian)
      true -> nil
    end
  end

  defp newest(units), do: Enum.max_by(units, fn {id, _unit} -> id end)

  defp unit_label(type), do: type |> Atom.to_string() |> String.replace("_", " ")

  # Shared gate every direct Bank command checks first — a no-op
  # (`{:error, :feudal_disabled}`) while `Game.feudal_enabled?/0` reads
  # `false` (prod's own default), same belt-and-suspenders status
  # `apply_income/3`'s own caller (`WorldServer.apply_bank/1`) already
  # carries for the turn-tick side of this same batch.
  defp ensure_feudal_enabled do
    if Game.feudal_enabled?(), do: :ok, else: {:error, :feudal_disabled}
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer`, matching the sibling `BrokenOaths.Units.Unit`/
  # `BrokenOaths.Diplomacy.Cooperation`'s own "pure, process-unaware,
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
