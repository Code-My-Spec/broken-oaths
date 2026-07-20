defmodule BrokenOaths.Game.API.Feudal do
  @moduledoc """
  Vassalage/vassalization, tribute, oath strain concessions, protection
  pacts, rebellion (including the Pact of Broken Oaths), stewardship,
  levies, the Gold Bank, and Honor — the feudal PvP batch (stories
  907-919). Thin `GenServer.call` wrappers onto each world's
  `BrokenOaths.Game.WorldServer`; see `BrokenOaths.Game`'s own moduledoc
  for the process architecture every function here round-trips through,
  and `BrokenOaths.Game.feudal_enabled?/0` for the single dormancy gate
  every one of these entry points respects.

  Extracted from `BrokenOaths.Game` (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target) — every function below is
  `defdelegate`d back onto `BrokenOaths.Game` unchanged, so no caller
  needs to know this module exists.
  """

  alias BrokenOaths.Game.WorldServer

  # -------------------------------------------------------------------
  # Vassalage / Tribute (stories 907/908)
  # -------------------------------------------------------------------

  @doc """
  The lord's own "Vassals" list in `world` (story 907/908):
  `[%{vassal_user_id:, email:, tribute_rate:, oath_strain:, levy_status:}]`
  for every ACTIVE vassalage `user` holds as lord — never carries the
  vassal's own secret Hidden Agenda (see `vassal_status/2`'s own doc
  for where that lives).
  """
  @spec vassals(map(), map()) :: [map()]
  def vassals(world, user), do: WorldServer.call(world, {:vassals, user})

  @doc """
  `user`'s own oath, if any: `%{lord_user_id:, lord_email:,
  tribute_rate:, oath_strain:, agenda_pending?:, levy_status:,
  lord_fallen?:}`, or `nil` for a free player. `agenda_pending?` is the
  Oath screen's own trigger — `true` until `choose_hidden_agenda/3`
  closes it. `lord_fallen?` (story 917) is `true` once the lord's own
  Lord unit is dead — `GameLive.Play`'s own "seize the moment" trigger.
  """
  @spec vassal_status(map(), map()) :: map() | nil
  def vassal_status(world, user), do: WorldServer.call(world, {:vassal_status, user})

  @doc """
  Record `user`'s own secret Hidden Agenda pick from the Oath screen —
  refused unless `user` is a vassal still awaiting one.
  """
  @spec choose_hidden_agenda(map(), map(), atom()) ::
          :ok | {:error, :not_a_vassal | Ecto.Changeset.t()}
  def choose_hidden_agenda(world, user, agenda),
    do: WorldServer.call(world, {:choose_hidden_agenda, user, agenda})

  @doc """
  Raise or lower `vassal_user_id`'s own tribute rate (0.0-1.0) — `user`
  must be their lord. Takes effect on the vassal's next turn boundary
  tribute.
  """
  @spec set_tribute_rate(map(), map(), term(), float()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def set_tribute_rate(world, user, vassal_user_id, rate),
    do: WorldServer.call(world, {:set_tribute_rate, user, vassal_user_id, rate})

  @doc """
  Issue a call to arms (story 908): `user` (the lord) calls
  `vassal_user_id` to pledge `share` (0, 1] of their standing army
  against `target_user_id` — a third player, never the lord or the
  vassal themselves.
  """
  @spec issue_levy(map(), map(), term(), term(), float()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def issue_levy(world, user, vassal_user_id, target_user_id, share),
    do: WorldServer.call(world, {:issue_levy, user, vassal_user_id, target_user_id, share})

  @doc "The vassal (`user`) answers their own lord's pending call to arms — they keep command of the pledged units."
  @spec answer_levy(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_found | Ecto.Changeset.t()}
  def answer_levy(world, user, lord_user_id),
    do: WorldServer.call(world, {:answer_levy, user, lord_user_id})

  @doc "The vassal (`user`) refuses their own lord's pending call — spikes their own Oath Strain."
  @spec refuse_levy(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_found | Ecto.Changeset.t()}
  def refuse_levy(world, user, lord_user_id),
    do: WorldServer.call(world, {:refuse_levy, user, lord_user_id})

  # -------------------------------------------------------------------
  # Oath Strain concessions / Protection Pact (stories 913/914)
  # -------------------------------------------------------------------

  @doc """
  `user` (the lord) gifts `vassal_user_id` — a one-off concession that
  eases their Oath Strain (`BrokenOaths.Game.OathStrain.ease_gift/1`).
  """
  @spec gift_vassal(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def gift_vassal(world, user, vassal_user_id),
    do: WorldServer.call(world, {:gift_vassal, user, vassal_user_id})

  @doc """
  `user` (the lord) and `vassal_user_id` declare `enemy_user_id` a
  shared enemy — eases the vassal's Oath Strain
  (`BrokenOaths.Game.OathStrain.ease_shared_enemy/1`).
  """
  @spec declare_shared_enemy(map(), map(), term(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def declare_shared_enemy(world, user, vassal_user_id, enemy_user_id),
    do: WorldServer.call(world, {:declare_shared_enemy, user, vassal_user_id, enemy_user_id})

  @doc """
  The vassal (`user`) marks their own bond with `lord_user_id`
  unhonored — spikes their own Oath Strain
  (`BrokenOaths.Game.OathStrain.spike_broken_protection_pact/1`). See
  `BrokenOaths.Game.WorldServer`'s own `handle_call/3` doc for how this
  narrow, vassal-driven seam differs from the real Protection Pact
  engine's own broken-pact resolution (a window genuinely expiring
  unanswered — story 914).
  """
  @spec mark_pact_unhonored(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def mark_pact_unhonored(world, user, lord_user_id),
    do: WorldServer.call(world, {:mark_pact_unhonored, user, lord_user_id})

  # -------------------------------------------------------------------
  # Rebellion (stories 915/919)
  # -------------------------------------------------------------------

  @doc """
  Read-only preview of what declaring independence against
  `lord_user_id` would do RIGHT NOW (story 915, criterion 7732): every
  one of `user`'s own occupied cities marked `will_rise?` per
  `BrokenOaths.Game.Rebellion.Resolution.city_rises?/4` (the SAME
  deterministic formula `declare_independence/3` itself commits with),
  plus the predicted temporary army size
  (`BrokenOaths.Game.Rebellion.Resolution.army_size/1`). Never live RNG,
  never a side effect — the same inputs (the lord's own Honor, this
  vassalage's own tribute rate, the world's own seed) produce the same
  verdicts calling this a hundred times in a row, and `declare_
  independence/3` recomputes the identical split from the identical
  inputs at commit time.
  """
  @spec independence_preview(map(), map(), term()) ::
          {:ok, %{cities: [%{city_id: term(), will_rise?: boolean()}], army_size: pos_integer()}}
          | {:error, :not_a_player | :not_a_vassal}
  def independence_preview(world, user, lord_user_id),
    do: WorldServer.call(world, {:independence_preview, user, lord_user_id})

  @doc """
  `user` (the vassal) declares independence from `lord_user_id` (story
  915): immediately severs the Vassalage (tribute stops the same turn
  boundary), resolves which of `user`'s own occupied cities rise back
  to them (`BrokenOaths.Game.Rebellion.Resolution.resolve_risings/4`) —
  each risen city de-occupies, restored to full health, and any of the
  former lord's own units still standing on it defect to `user` — spawns
  a temporary rebellion army (`BrokenOaths.Game.Rebellion.Resolution.
  army_size/1`) flagged `temporary: true`, and opens a state of war
  between the two (a narrow, rebellion-scoped PvP exception —
  `BrokenOaths.Combat.Resolver.hostile?/2` itself never changes). Creates a
  persisted, first-class `BrokenOaths.Game.Rebellion` row (`status:
  :active`) naming both parties and recording the split, the army size,
  and the start turn.
  """
  @spec declare_independence(map(), map(), term()) ::
          {:ok, BrokenOaths.Game.Rebellion.t()}
          | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def declare_independence(world, user, lord_user_id),
    do: WorldServer.call(world, {:declare_independence, user, lord_user_id})

  @doc """
  Story 917: whether `lord_user_id`'s own Lord unit is currently dead
  on the board — "the lord has fallen, seize the moment." Read fresh
  off live state every call (never cached), so a caller like `GameLive.
  Play`'s own `"declare_independence"` handler can decide, at the
  instant of the click, whether to skip story 915's two-step confirm
  (the lord is already gone — there is nothing further to warn about)
  or raise it as usual (the lord is still alive).
  """
  @spec lord_fallen?(map(), term()) :: boolean()
  def lord_fallen?(world, lord_user_id),
    do: WorldServer.call(world, {:lord_fallen?, lord_user_id})

  @doc """
  `user`'s own active-or-most-recent Rebellion as REBEL, or `nil` if
  they've never declared one: `%{id:, status:, rebel_user_id:,
  rebel_email:, former_lord_user_id:, former_lord_email:, started_turn:,
  army_size:, risen_city_ids:, loyal_city_ids:}`. Once a rebellion ends
  (`independence_won`/`crushed`/`peace`) this keeps reading that same
  settled row — a rebel only ever carries one ACTIVE rebellion at a
  time (`BrokenOaths.Game.Rebellion`'s own moduledoc).
  """
  @spec rebellion_status(map(), map()) :: map() | nil
  def rebellion_status(world, user), do: WorldServer.call(world, {:rebellion_status, user})

  @doc """
  Every Rebellion (active or ended) raised against `user` as the FORMER
  LORD — same shape as `rebellion_status/2`'s own single map, one per
  row, freshest first.
  """
  @spec rebellions_as_lord(map(), map()) :: [map()]
  def rebellions_as_lord(world, user), do: WorldServer.call(world, {:rebellions_as_lord, user})

  @doc """
  Either side of an active Rebellion between `user` and
  `counterparty_user_id` offers a negotiated peace (story 919):
  `outcome` is `"independence"` (the rebel is granted full freedom) or
  `"restored_vassal"` (the rebel swears fealty again) — nobody loses
  cities either way. `reparations_gold` (optional) moves from whoever
  accepts to whoever offers once `accept_peace/3` closes the deal. A
  fresh offer replaces any prior one still pending for this same
  Rebellion.
  """
  @spec offer_peace(map(), map(), term(), String.t(), non_neg_integer() | nil) ::
          :ok | {:error, :not_a_player | :no_active_rebellion}
  def offer_peace(world, user, counterparty_user_id, outcome, reparations_gold),
    do:
      WorldServer.call(
        world,
        {:offer_peace, user, counterparty_user_id, outcome, reparations_gold}
      )

  @doc """
  `user` accepts `counterparty_user_id`'s own pending peace offer —
  refused unless one is actually pending FROM the counterparty. Ends
  the Rebellion `:peace`, frees every one of the rebel's own cities
  (risen or loyal — "nobody loses cities in a peace"), disbands the
  temporary rebellion army, and moves any agreed reparations.
  """
  @spec accept_peace(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :no_active_rebellion | :no_pending_offer}
  def accept_peace(world, user, counterparty_user_id),
    do: WorldServer.call(world, {:accept_peace, user, counterparty_user_id})

  @doc "`user` rejects `counterparty_user_id`'s own pending peace offer — the war simply continues, the Rebellion stays `:active`."
  @spec reject_peace(map(), map(), term()) :: :ok | {:error, :not_a_player | :no_active_rebellion}
  def reject_peace(world, user, counterparty_user_id),
    do: WorldServer.call(world, {:reject_peace, user, counterparty_user_id})

  # -------------------------------------------------------------------
  # Coordinated Rebellion — Pact of Broken Oaths (story 916)
  # -------------------------------------------------------------------

  @doc """
  `user`'s own membership in an active (`:forming`) Pact of Broken
  Oaths, or `nil` if they aren't currently a member of one: `%{id:,
  strike_turn:, own_status:, informer?:, members: [%{user_id:, email:,
  status:}]}`. Every OTHER member's own `status` is always `:invited`
  ("Outstanding") regardless of their real, secret commit answer —
  only the reader's own row (`own_status`) ever tells the truth,
  criterion 7738's own secrecy rule.
  """
  @spec pact_view(map(), map()) :: map() | nil
  def pact_view(world, user), do: WorldServer.call(world, {:pact_view, user})

  @doc """
  Every FELLOW vassal of `user`'s own lord — the eligible-to-invite
  roster a pact composer offers (criterion 7737's own "only fellow
  vassals of the same lord are eligible"). `[]` for a free player, or
  for a vassal with no fellow vassals under the same lord.
  """
  @spec pact_candidates(map(), map()) :: [%{user_id: term(), email: String.t()}]
  def pact_candidates(world, user), do: WorldServer.call(world, {:pact_candidates, user})

  @doc """
  `user` (a vassal) opens a Pact of Broken Oaths against their own
  lord, naming `strike_turn` (a positive integer of turn BOUNDARIES
  from right now, not an absolute world-turn number) and inviting
  `invitee_user_ids` into it — chat membership IS the conspiracy
  roster. An invitee who isn't a fellow vassal of the SAME lord is
  silently dropped, never rejecting the call outright. `user` becomes
  a member of their own pact too (`:invited`, same as any other
  invitee — they still `pact_commit/2` explicitly).
  """
  @spec open_pact_chat(map(), map(), pos_integer() | String.t(), [term()]) ::
          {:ok, BrokenOaths.Game.RebellionPact.t()}
          | {:error, :not_a_player | :not_a_vassal | :invalid_strike_turn | Ecto.Changeset.t()}
  def open_pact_chat(world, user, strike_turn, invitee_user_ids),
    do: WorldServer.call(world, {:open_pact_chat, user, strike_turn, invitee_user_ids})

  @doc "`user` secretly commits to strike with their own pact — reversible any time before the strike turn."
  @spec pact_commit(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  def pact_commit(world, user), do: WorldServer.call(world, {:pact_commit, user})

  @doc "`user` secretly declines to strike with their own pact — reversible any time before the strike turn."
  @spec pact_decline(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  def pact_decline(world, user), do: WorldServer.call(world, {:pact_decline, user})

  @doc """
  `user` secretly informs their own pact's targeted lord of the plot,
  for a personal reward — their identity stays hidden from every
  OTHER member (criterion 7741). Informing changes no odds; it only
  warns the lord, who can then pre-empt.
  """
  @spec pact_inform(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  def pact_inform(world, user), do: WorldServer.call(world, {:pact_inform, user})

  @doc """
  `user`'s own warning that a plot against them has been informed on,
  or `nil` while no member of any of their own pacts has informed:
  `%{strike_turn:}`. Never carries the informer's own identity, nor
  the rest of the roster.
  """
  @spec pact_informed_notice(map(), map()) :: %{strike_turn: pos_integer()} | nil
  def pact_informed_notice(world, user),
    do: WorldServer.call(world, {:pact_informed_notice, user})

  @doc """
  `user`'s own coarse conspiracy "heat" gauge (story 916, criterion
  7742): the mean `BrokenOaths.Game.Vassalage.oath_strain` across
  every one of their own ACTIVE vassals — a needle, never the pact
  chat's own content. `0` for a lord with no vassals.
  """
  @spec conspiracy_heat(map(), map()) :: BrokenOaths.Game.OathStrain.strain()
  def conspiracy_heat(world, user), do: WorldServer.call(world, {:conspiracy_heat, user})

  @doc "`user` (a lord) fully heals every one of their own cities — a pre-emptive defensive brace once warned of a plot."
  @spec brace_defenses(map(), map()) :: :ok | {:error, :not_a_player}
  def brace_defenses(world, user), do: WorldServer.call(world, {:brace_defenses, user})

  @doc "`user` (a lord) fully heals their own Lord unit — a pre-emptive reposition once warned of a plot."
  @spec reposition_lord(map(), map()) :: :ok | {:error, :not_a_player | :no_lord_unit}
  def reposition_lord(world, user), do: WorldServer.call(world, {:reposition_lord, user})

  @doc """
  `user` (a lord) eases EVERY one of their own vassals' Oath Strain by
  `BrokenOaths.Game.OathStrain.gift_ease/0` at once — a broad
  concession a warned lord can make without knowing which of their
  vassals is actually plotting (the roster stays secret even once
  informed).
  """
  @spec buy_off_conspirators(map(), map()) :: :ok | {:error, :not_a_player}
  def buy_off_conspirators(world, user),
    do: WorldServer.call(world, {:buy_off_conspirators, user})

  @doc """
  `user` (a lord) honors an overdue Protection Pact call for
  `vassal_user_id`, easing their Oath Strain by
  `BrokenOaths.Game.OathStrain.autonomy_ease/0` — a targeted
  concession, alongside the real `set_tribute_rate/4`, story 916's own
  "lowers tribute rates and honors an overdue protection call" lever.
  """
  @spec honor_protection_call(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def honor_protection_call(world, user, vassal_user_id),
    do: WorldServer.call(world, {:honor_protection_call, user, vassal_user_id})

  # -------------------------------------------------------------------
  # Gold Bank (story 909)
  # -------------------------------------------------------------------

  @doc "`user`'s own bank status: `%{gold:, cap:}` (`BrokenOaths.Game.Bank.status/1`)."
  @spec bank(map(), map()) :: %{gold: non_neg_integer(), cap: pos_integer()}
  def bank(world, user), do: WorldServer.call(world, {:bank, user})

  @doc "Sweep `user`'s own bank into their treasury — a no-op against an already-empty bank, never refused."
  @spec collect_bank(map(), map()) :: :ok | {:error, :not_a_player | :feudal_disabled}
  def collect_bank(world, user), do: WorldServer.call(world, {:collect_bank, user})

  @doc "Raise `user`'s own bank cap for `BrokenOaths.Game.Bank.upgrade_cost/1`'s own gold price — refused outright when unaffordable."
  @spec upgrade_bank(map(), map()) ::
          :ok | {:error, :not_a_player | :insufficient_gold | :feudal_disabled}
  def upgrade_bank(world, user), do: WorldServer.call(world, {:upgrade_bank, user})

  # -------------------------------------------------------------------
  # Feudal Stewardship (story 910)
  # -------------------------------------------------------------------

  @doc "`user`'s own world-visible Honor reputation figure (`BrokenOaths.Players.Player.honor`)."
  @spec honor(map(), map()) :: integer()
  def honor(world, user), do: WorldServer.call(world, {:honor, user})

  @doc "`user`'s own full steward-action audit trail — every action taken on their behalf while offline, freshest first."
  @spec steward_log(map(), map()) :: [map()]
  def steward_log(world, user), do: WorldServer.call(world, {:steward_log, user})

  @doc """
  `steward_user` sweeps `owner_user_id`'s own offline Gold Bank
  entirely into the OWNER's treasury — pure stewardship, the steward's
  own treasury never moves. Refused unless `steward_user` is the
  owner's lord, a fellow vassal of the same lord, or an accepted ally
  (`BrokenOaths.Game.Stewardship.eligible?/1`), AND `owner_user_id` is
  genuinely offline (`BrokenOaths.Players.Presence.online?/2`).
  """
  @spec steward_collect_bank(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_eligible | :owner_online | :feudal_disabled}
  def steward_collect_bank(world, steward_user, owner_user_id),
    do: WorldServer.call(world, {:steward_collect_bank, steward_user, owner_user_id})

  @doc """
  `steward_user` sets `owner_user_id`'s own production queue —
  constructive-only, same eligibility gate as `steward_collect_bank/3`.
  """
  @spec steward_queue_production(map(), map(), term(), term(), atom() | String.t()) ::
          :ok
          | {:error,
             :not_a_player
             | :not_eligible
             | :owner_online
             | :not_found
             | :not_constructive
             | :invalid_item
             | :feudal_disabled
             | atom()}
  def steward_queue_production(world, steward_user, owner_user_id, city_id, type),
    do:
      WorldServer.call(
        world,
        {:steward_queue_production, steward_user, owner_user_id, city_id, type}
      )

  @doc "Always refused — \"no cancel-griefing\" (story 910); no path anywhere ever reaches the real cancel command for a steward."
  @spec steward_cancel_production_item(map(), map(), term(), term(), term()) ::
          {:error, :not_constructive}
  def steward_cancel_production_item(world, steward_user, owner_user_id, city_id, item_id),
    do:
      WorldServer.call(
        world,
        {:steward_cancel_production_item, steward_user, owner_user_id, city_id, item_id}
      )

  @doc "Always refused — \"no disbanding\" (story 910); no disband mechanic exists anywhere in this codebase yet, for anyone."
  @spec steward_disband_unit(map(), map(), term(), term()) :: {:error, :not_constructive}
  def steward_disband_unit(world, steward_user, owner_user_id, unit_id),
    do: WorldServer.call(world, {:steward_disband_unit, steward_user, owner_user_id, unit_id})

  @doc "Always refused — the default-closed baseline `steward_defend/4`'s own emergency exception opens against."
  @spec steward_queue_move(map(), map(), term(), term(), term()) :: {:error, :not_allowed}
  def steward_queue_move(world, steward_user, owner_user_id, unit_id, to_tile \\ nil),
    do:
      WorldServer.call(
        world,
        {:steward_queue_move, steward_user, owner_user_id, unit_id, to_tile}
      )

  @doc "Always refused — a steward may never launch aggression, even mid-emergency (story 910)."
  @spec steward_attack(map(), map(), term(), term(), term()) :: {:error, :not_allowed}
  def steward_attack(world, steward_user, owner_user_id, unit_id, target_camp_id \\ nil),
    do:
      WorldServer.call(
        world,
        {:steward_attack, steward_user, owner_user_id, unit_id, target_camp_id}
      )

  @doc """
  EMERGENCY DEFENSE: `steward_user` orders `owner_user_id`'s own unit
  to a strictly adjacent, defensive `to_tile` — refused unless eligible
  AND `owner_user_id` is both offline and currently
  `BrokenOaths.Game.Stewardship.under_attack?/1`. An eligible steward
  who overreaches the destination during a genuine emergency window is
  provable sabotage: the move is still refused, but the attempt is
  logged and dings the STEWARD's own Honor.
  """
  @spec steward_defend(map(), map(), term(), term(), term()) ::
          :ok
          | {:error,
             :not_a_player
             | :not_eligible
             | :owner_online
             | :not_owner
             | :not_under_attack
             | :unreachable
             | :feudal_disabled}
  def steward_defend(world, steward_user, owner_user_id, unit_id, to_tile),
    do: WorldServer.call(world, {:steward_defend, steward_user, owner_user_id, unit_id, to_tile})

  # -------------------------------------------------------------------
  # Test-only seams (gold/honor, feudal-adjacent)
  # -------------------------------------------------------------------

  @doc """
  Test-only: set `user`'s own gold treasury directly, standing in for a
  per-turn city gold YIELD this codebase has no real source for yet —
  see `BrokenOaths.Game.WorldServer`'s `:set_player_gold_for_test`
  handler for the same documented, narrow-exception status
  `set_unit_hp_for_test/3` already has.
  """
  @spec set_player_gold_for_test(map(), map(), integer()) :: :ok
  def set_player_gold_for_test(world, user, gold),
    do: WorldServer.call(world, {:set_player_gold_for_test, user.id, gold})

  @doc """
  Test-only: declares `user`'s per-turn gold INCOME, separate from
  their actual treasury balance (`set_player_gold_for_test/3`) — see
  `BrokenOaths.Game.WorldServer`'s `:set_player_gold_income_for_test`
  handler for the full rationale and its CURRENT, narrower status now
  that story 912 shipped a real per-turn city gold income mechanic:
  `apply_tribute/1`/`apply_bank/1` compute their own figure straight
  from `Yields.city_gold_income/2` every turn boundary and no longer
  read this seam at all — it's kept only for narrower, not-yet-
  reconciled test scenarios that still want a hand-declared income
  independent of any real city.
  """
  @spec set_player_gold_income_for_test(map(), map(), integer()) :: :ok
  def set_player_gold_income_for_test(world, user, income),
    do: WorldServer.call(world, {:set_player_gold_income_for_test, user.id, income})

  @doc """
  Test-only: set `user`'s own world-visible Honor reputation
  (`BrokenOaths.Players.Player.honor`) directly, same narrow, documented-
  bridge status as `set_player_gold_for_test/3` — a direct precondition
  setter for Honor, standing in for however many dishonorable acts it
  would otherwise take to depress it to a specific figure (`Siege.
  apply_execute_honor_penalty/1` only ever moves it by small, fixed
  steps). Never used to fabricate a RESULT this codebase computes itself
  (e.g. a rebellion's own `risen_city_ids` — `Rebellion.Resolution.
  city_rises?/4` still does that math for real, off whatever Honor this
  sets) — only the lord's own starting reputation.
  """
  @spec set_player_honor_for_test(map(), map(), integer()) :: :ok
  def set_player_honor_for_test(world, user, honor),
    do: WorldServer.call(world, {:set_player_honor_for_test, user.id, honor})
end
