defmodule BrokenOaths.Game.Bank do
  @moduledoc """
  Gold-bank core for story 909: pure business rules on top of the
  `banked_gold`/`bank_cap` fields living directly on `BrokenOaths.Game.
  Player` (migration `20260718130000`) — mirrors `BrokenOaths.Game.
  Tribute`'s own "pure math, no `Repo`" role. `BrokenOaths.Game.
  WorldServer` is the imperative shell: it reads each player's own
  REAL per-turn gold income (story 912 — `BrokenOaths.Game.Yields.
  city_gold_income/2` summed over every city they own,
  `WorldServer.gold_income_by_player/1`; the test-only `state.
  test_gold_income` seam `BrokenOaths.Game.Tribute`'s own moduledoc
  used to document is no longer this phase's source) and whether they
  currently hold a live connection (`BrokenOaths.Game.
  Presence.online?/2`), calls `settle_income/3` once per player per
  turn boundary, and persists the result the same "diff `state.
  players`, `Repo.update_all` the changed rows" way every other
  in-tick gold change already does.

  ## Logged in vs. offline

  `settle_income/3` is the whole turn-tick contract: a LOGGED IN
  player's income flows straight to their usable treasury (`gold`);
  an OFFLINE player's income accrues into their own capped bank
  (`banked_gold`, `bank_cap`) instead, via `accrue/3`. Once the bank is
  FULL, further offline income is simply wasted — never lost from
  `gold` (nothing was ever there to lose), never negative, and never
  carried over once the player logs back in and collects: the point is
  "return or be tended," not "bank forever." A non-positive income
  moves nothing either way (mirrors `Tribute.tribute_amount/2`'s own
  "zero or negative income skims nothing" rule).

  ## Collect and upgrade

  `collect/1` is the deliberate engagement tap: sweep the ENTIRE bank
  into the treasury in one motion, emptying it — the same math
  `BrokenOaths.Game.Stewardship`'s own bank-sweep action reuses
  (`steward_collect/1`, an alias kept separate only so each call site
  documents its own actor). `upgrade/1` is the real economy decision:
  raise the cap for a gold cost, refused outright (no partial charge)
  when the player can't afford it.
  """

  alias BrokenOaths.Game.Player

  @type player :: %{gold: integer(), banked_gold: integer(), bank_cap: integer()}

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
  function so `BrokenOaths.Game.Stewardship`'s call site documents
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
end
