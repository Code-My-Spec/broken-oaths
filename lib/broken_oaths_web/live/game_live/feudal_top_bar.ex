defmodule BrokenOathsWeb.GameLive.FeudalTopBar do
  @moduledoc """
  The top bar's own feudal-relationship chrome — mounted by
  `BrokenOathsWeb.GameLive.Play` immediately after the gold badge,
  entirely gated (implicitly, via each underlying `Game` read already
  reporting empty/`nil`) on `Game.feudal_enabled?/0`, the same posture
  that module's own doc establishes for the rest of this batch.

  Bundles every vassalage/tribute/rebellion/pact/protection surface
  together (stories 906-919) since they're tightly interdependent —
  the Bank/Honor/Steward Log badges, the lord's own Vassals dropdown
  and conspiracy-heat gauge, a pact-informed warning banner, every
  Rebellion raised against this player as the former lord, the
  conqueror's own Captured Cities dropdown, the "seize the moment"
  prompt, a subjugated player's own oath status (tribute rate, Oath
  Strain, levy Answer/Refuse, Declare Independence), the Pact of
  Broken Oaths composer + chat, and the rebel's own war status. A
  purely presentational function component: `Play` owns every command
  dispatch and every one of these read models, this only ever renders
  the assigns it's given — no `BrokenOaths.Game` read of its own, the
  same posture `GameLive.UnitPanel`/`GameLive.CityPanel` already
  establish.
  """

  use BrokenOathsWeb, :html

  attr :feudal_enabled?, :boolean, required: true
  attr :bank, :any, required: true
  attr :bank_error, :any, required: true
  attr :honor, :any, required: true
  attr :steward_log, :list, required: true
  attr :allow_steward_production, :boolean, required: true
  attr :vassals, :list, required: true
  attr :known_players, :list, required: true
  attr :conspiracy_heat, :any, required: true
  attr :pact_informed, :any, required: true
  attr :rebellions_as_lord, :list, required: true
  attr :user, :map, required: true
  attr :captured_cities, :list, required: true
  attr :vassal_status, :any, required: true
  attr :declare_independence_lord_user_id, :any, required: true
  attr :independence_preview, :any, required: true
  attr :rebellion_status, :any, required: true
  attr :pact, :any, required: true
  attr :pact_panel_open?, :boolean, required: true
  attr :pact_candidates, :list, required: true

  def panel(assigns) do
    ~H"""
    <%= if @feudal_enabled? do %>
      <%!-- Story 909: the Gold Bank — holdings/cap badges +
               Collect/Upgrade, always mounted (a fresh player's own
               bank starts empty, never absent). --%>
      <.live_component
        module={BrokenOathsWeb.GameLive.BankPanel}
        id="bank-panel"
        bank={@bank}
        error={@bank_error}
      />

      <%!-- Story 910: the world-visible Honor reputation figure —
               sibling to `player-gold`/the bank badges above. The
               number lives in its OWN innermost
               `data-test="player-honor"` span (icon kept OUTSIDE it) —
               mirrors `BankPanel`'s own `bank-gold`/`bank-cap`
               structure, since a spec's own `data-test="player-honor"[^>]*>(-?\d+)`
               regex needs the digit immediately after that span's own
               closing tag, not after a sibling icon's markup. --%>
      <span class="badge badge-outline gap-1" title="Honor">
        <.icon name="hero-scale" class="w-3 h-3" />
        <span data-test="player-honor">{@honor}</span>
      </span>

      <%!-- Playtest issue 340c1ad4: the owner's own EMPIRE-WIDE grant
               — whether ANY eligible steward may set my production
               while I'm offline, opt-in and off by default. Sibling to
               the Honor badge above, always mounted (a fresh player's
               own grant reads a real, renderable `false`, not an
               absent one). Clicking sends the OPPOSITE of the current
               value; `Play`'s own `"set_allow_steward_production"`
               handler always sets the CALLER's own flag, covering
               every city they have, never a single one. --%>
      <label class="badge badge-outline gap-1 cursor-pointer" title="Allow my steward to set my production">
        <input
          type="checkbox"
          checked={@allow_steward_production}
          phx-click="set_allow_steward_production"
          phx-value-allowed={to_string(!@allow_steward_production)}
          data-test="allow-steward-production-toggle"
          class="checkbox checkbox-xs"
        />
        Steward: Production
      </label>

      <%!-- Story 910: every steward action taken on my own behalf
               while I was away — always mounted (an empty log is a
               real, renderable state, not an absent one). --%>
      <.steward_log_panel steward_log={@steward_log} />
    <% end %>

    <%!-- Story 907: the lord's own Vassals list — only mounted while
             non-empty (criterion 7667's own "no vassals-list at all"
             anchor). --%>
    <.vassals_panel :if={@vassals != []} vassals={@vassals} known_players={@known_players} />

    <%!-- Story 916, criterion 7742 — the lord's own coarse
             conspiracy "heat" gauge: a needle, never the pact chat's
             own content. Same "no element at all with nothing to show"
             posture `vassals_panel` above already has. --%>
    <span
      :if={@vassals != []}
      class="badge badge-outline gap-1"
      title="Conspiracy Heat"
    >
      <.icon name="hero-fire" class="w-3 h-3" />
      <span data-test="conspiracy-heat">{@conspiracy_heat}</span>
    </span>

    <%!-- Story 916, criterion 7741 — the lord's own warning once a
             member of a pact against her has informed: the strike turn
             plus her three pre-emption levers. Never the roster, never
             the informer's own identity. --%>
    <div :if={@pact_informed} class="flex items-center gap-1" data-test="pact-informed-banner">
      <span class="badge badge-error gap-1">
        <.icon name="hero-exclamation-triangle" class="w-3 h-3" />
        A vassal has warned you of a plot to strike on turn {@pact_informed.strike_turn}
      </span>
      <button
        type="button"
        phx-click="brace_defenses"
        data-test="brace-defenses"
        class="btn btn-xs btn-outline"
      >
        Brace Defenses
      </button>
      <button
        type="button"
        phx-click="reposition_lord"
        data-test="reposition-lord"
        class="btn btn-xs btn-outline"
      >
        Reposition Lord
      </button>
      <button
        type="button"
        phx-click="buy_off_conspirators"
        data-test="buy-off-conspirators"
        class="btn btn-xs btn-outline"
      >
        Buy Off Conspirators
      </button>
    </div>

    <%!-- Stories 915/919 — every Rebellion (active or ended) raised
             against this player as the FORMER LORD: the "at war" badge
             (only while still active) plus the persisted Rebellion
             panel itself (criterion 7747). --%>
    <div :for={rebellion <- @rebellions_as_lord} class="flex items-center gap-1">
      <span
        :if={rebellion.status == :active}
        class="badge badge-error gap-1"
        data-test="at-war-with"
      >
        <.icon name="hero-fire" class="w-3 h-3" /> At war with {rebellion.rebel_name}
      </span>

      <.rebellion_panel rebellion={rebellion} viewer_user_id={@user.id} />
    </div>

    <%!-- QA issue ffa66192: the conqueror's own captured-city
             tracker — only mounted while non-empty, same "no element at
             all while there's nothing to show" posture `vassals_panel`
             above already has. Surfaces the Execute/Release choice for
             any still-living fallen garrison. --%>
    <.captured_cities_panel
      :if={@captured_cities != []}
      captured_cities={@captured_cities}
    />

    <%!-- Story 917 — a durable, re-mountable "seize the moment"
             prompt: rendered any time this vassal's own oath is still
             active AND their lord's own Lord unit is currently dead
             (`@vassal_status.lord_fallen?`), so it survives a fresh
             mount/reconnect rather than a fire-once toast a player
             could simply miss. Nests the SAME `"declare_independence"`
             action (story 915) directly inside the prompt — clicking
             it now commits immediately (see that event's own
             `handle_event/3` doc for why a dead lord skips the
             two-step confirm). --%>
    <div
      :if={@vassal_status && @vassal_status.lord_fallen?}
      class="alert alert-warning flex items-center gap-2"
      data-test="seize-the-moment-prompt"
    >
      <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
      <span>Your lord has fallen — seize the moment</span>
      <button
        type="button"
        phx-click="declare_independence"
        phx-value-lord_user_id={@vassal_status.lord_user_id}
        data-test="declare-independence-action"
        class="btn btn-xs btn-error"
      >
        Declare Independence
      </button>
    </div>

    <%!-- Story 907/908: a subjugated player's own oath — sworn-to
             badge, the rate they feel, and their own latest levy status
             — plus, QA issue dae2e65d, real Answer/Refuse controls
             while a call to arms is still pending. --%>
    <div :if={@vassal_status} class="flex items-center gap-1">
      <span class="badge badge-secondary gap-1" data-test="vassal-status">
        Sworn to {@vassal_status.lord_name}
      </span>
      <span class="badge badge-outline" data-test="my-tribute-rate">
        {tribute_rate_label(@vassal_status.tribute_rate)}
      </span>
      <%!-- Story 913: the vassal's OWN read of their Oath Strain —
               sibling to `my-tribute-rate` above, same "icon outside,
               digit in its own innermost span" structure `player-honor`
               already sets, since a spec's own
               `data-test="my-oath-strain"[^>]*>(\d+)` regex needs the
               digit immediately after this span's own opening tag. --%>
      <span class="badge badge-outline gap-1" title="Oath Strain">
        <.icon name="hero-fire" class="w-3 h-3" />
        <span data-test="my-oath-strain">{@vassal_status.oath_strain}</span>
      </span>
      <span :if={@vassal_status.levy_status} class="badge badge-outline" data-test="levy-status">
        {@vassal_status.levy_status}
      </span>
      <%!-- Story 914: a Protection Pact call actively raised for
               THIS vassal — only rendered while one is active, same
               "no element at all with nothing to show" posture
               `levy-status` above already has. --%>
      <span
        :if={@vassal_status.protection_call}
        class="badge badge-error badge-sm"
        data-test="my-protection-call"
      >
        Under attack — protection requested from {@vassal_status.lord_name} (<span data-test="my-protection-window">{@vassal_status.protection_call.window_remaining}</span> turns left)
      </span>
      <button
        :if={@vassal_status.protection_call}
        type="button"
        phx-click="mark_pact_unhonored"
        phx-value-lord_user_id={@vassal_status.lord_user_id}
        data-test="mark-pact-unhonored"
        class="btn btn-xs btn-outline btn-error"
      >
        Mark Unhonored
      </button>
      <%!-- QA issue dae2e65d — the vassal's own Answer/Refuse
               controls, only while a call to arms actually awaits a
               response (`:pending`); `:answered`/`:refused` are past
               tense, the badge above alone. --%>
      <button
        :if={@vassal_status.levy_status == :pending}
        type="button"
        phx-click="answer_levy"
        phx-value-lord_user_id={@vassal_status.lord_user_id}
        data-test="answer-levy"
        class="btn btn-xs btn-primary"
      >
        Answer
      </button>
      <button
        :if={@vassal_status.levy_status == :pending}
        type="button"
        phx-click="refuse_levy"
        phx-value-lord_user_id={@vassal_status.lord_user_id}
        data-test="refuse-levy"
        class="btn btn-xs btn-outline btn-error"
      >
        Refuse
      </button>

      <%!-- Story 915 — the irreversible choice: step one raises the
               confirming warning below, commits nothing. --%>
      <button
        type="button"
        phx-click="declare_independence"
        phx-value-lord_user_id={@vassal_status.lord_user_id}
        data-test="declare-independence"
        class="btn btn-xs btn-outline btn-error"
      >
        Declare Independence
      </button>
    </div>

    <%!-- Story 916 — Pact of Broken Oaths: a vassal's own
             conspiracy composer, mirrors `alliance-button`/`chat-button`'s
             own toggle shape. Only ever rendered for an actual vassal —
             a free player has no lord to conspire against, and the
             lord themself is never a FELLOW vassal (criterion 7737's
             own second `then_`). --%>
    <div :if={@vassal_status} class="relative">
      <button
        type="button"
        data-test="pact-button"
        phx-click="toggle_pact_panel"
        class="btn btn-sm btn-ghost gap-1"
      >
        <.icon name="hero-user-group" class="w-4 h-4" />
      </button>

      <div
        :if={@pact_panel_open?}
        data-test="pact-panel"
        class="card bg-base-200 shadow-xl w-80 absolute top-full right-0 mt-1 z-10"
      >
        <div class="card-body p-3 gap-2">
          <h3 class="card-title text-sm">Pact of Broken Oaths</h3>

          <p :if={@pact_candidates == []} class="text-xs opacity-60">
            No fellow vassals to invite yet.
          </p>

          <form phx-submit="open_pact_chat" class="flex flex-col gap-2">
            <div
              :for={candidate <- @pact_candidates}
              data-test={"fellow-vassal-#{candidate.user_id}"}
              class="flex items-center gap-2 text-sm"
            >
              <input
                type="checkbox"
                name="invitee_user_ids[]"
                value={candidate.user_id}
                class="checkbox checkbox-xs"
              />
              <span class="truncate">{candidate.display_name}</span>
            </div>

            <div class="flex items-center gap-1">
              <span class="text-xs">Strike in</span>
              <input
                type="number"
                name="strike_turn"
                min="1"
                value="50"
                class="input input-xs input-bordered w-16"
              />
              <span class="text-xs">turns</span>
            </div>

            <button
              type="submit"
              data-test="open-pact-chat"
              class="btn btn-xs btn-primary self-start"
            >
              Open Pact Chat
            </button>
          </form>
        </div>
      </div>
    </div>

    <%!-- Story 916 — the pact chat itself, visible on every MEMBER's
             own view once the pact exists (including the initiator).
             Roster status is masked per criterion 7738: every OTHER
             member always reads "Outstanding" regardless of their
             real, secret answer; only the reader's own row tells the
             truth. Commit/decline stay available even after an answer
             is already on record (criterion 7742's own "still a
             negotiation" reversibility). --%>
    <div :if={@pact} data-test="pact-chat" class="card bg-base-200 shadow-xl w-80">
      <div class="card-body p-3 gap-2">
        <h3 class="card-title text-sm">Pact of Broken Oaths — strike turn {@pact.strike_turn}</h3>

        <div
          :if={@pact.own_status == :invited}
          data-test="pact-invite-notice"
          class="alert alert-warning p-2 text-xs"
        >
          You've been invited into a pact of rebellion.
        </div>

        <div
          :if={@pact.informer?}
          data-test="informer-reward"
          class="alert alert-success p-2 text-xs"
        >
          Your informing has been rewarded — tribute forgiven, land granted.
        </div>

        <div data-test="pact-roster" class="flex flex-col gap-1">
          <div
            :for={member <- @pact.members}
            data-test={"pact-member-#{member.user_id}"}
            class="flex items-center justify-between text-xs"
          >
            <span class="truncate">{member.display_name}</span>
            <span data-test={"pact-member-status-#{member.user_id}"}>
              {pact_status_label(member.status)}
            </span>
          </div>
        </div>

        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click="pact_commit"
            data-test="pact-commit"
            class="btn btn-xs btn-primary"
          >
            Commit
          </button>
          <button
            type="button"
            phx-click="pact_decline"
            data-test="pact-decline"
            class="btn btn-xs btn-outline"
          >
            Decline
          </button>
          <button
            type="button"
            phx-click="pact_inform"
            data-test="pact-inform"
            class="btn btn-xs btn-outline btn-error"
          >
            Inform Lord
          </button>
        </div>
      </div>
    </div>

    <%!-- Story 915 — the confirming warning: a second, explicit
             click actually severs the oath (`"confirm_declare_
             independence"`). --%>
    <div
      :if={@declare_independence_lord_user_id}
      class="modal modal-open"
      data-test="declare-independence-warning"
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg">Declare Independence?</h3>
        <p class="py-2 opacity-70">
          This immediately severs your oath and opens a state of war. There is no going back.
        </p>
        <div class="modal-action">
          <button phx-click="declare_independence_cancel" class="btn btn-ghost">Cancel</button>
          <button
            type="button"
            phx-click="confirm_declare_independence"
            phx-value-lord_user_id={@declare_independence_lord_user_id}
            class="btn btn-error"
            data-test="confirm-declare-independence"
          >
            Confirm — Declare Independence
          </button>
        </div>
      </div>
    </div>

    <%!-- Story 915, criterion 7732 — the read-only preview: each
             occupied city marked will-rise/stays-loyal plus the
             predicted temporary army size, entirely before the player
             commits (no hidden dice roll). --%>
    <div
      :if={@independence_preview}
      class="flex items-center gap-1"
      data-test="independence-preview"
    >
      <span
        :for={city <- @independence_preview.cities}
        class="badge badge-outline badge-sm"
        data-test={"rise-preview-city-#{city.city_id}"}
      >
        {if city.will_rise?, do: "will rise", else: "stays loyal"}
      </span>
      <span class="badge badge-outline gap-1" title="Predicted rebellion army">
        <.icon name="hero-users" class="w-3 h-3" />
        <span data-test="rebellion-army-preview">{@independence_preview.army_size}</span>
      </span>
    </div>

    <%!-- Stories 915/919 — the rebel's own war state: the "at war"
             badge (only while the Rebellion is still active) and the
             persisted, first-class Rebellion panel, any status — the
             story-919 lifecycle settles it exactly once and this keeps
             reading that same row. --%>
    <div :if={@rebellion_status} class="flex items-center gap-1">
      <span
        :if={@rebellion_status.status == :active}
        class="badge badge-error gap-1"
        data-test="at-war-with"
      >
        <.icon name="hero-fire" class="w-3 h-3" /> At war with {@rebellion_status.former_lord_name}
      </span>

      <.rebellion_panel rebellion={@rebellion_status} viewer_user_id={@user.id} />
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Vassalage / Tribute components (stories 906/907/908)
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # Rebellion components (stories 915/919)
  # -------------------------------------------------------------------

  # The persisted, first-class Rebellion panel — new judgment call,
  # criterion 7747: `data-test="rebellion-panel"` wraps every field the
  # design doc calls for (status, both parties, the start turn, the
  # spawned army size, and the risen/contested city counts), rendered
  # identically on BOTH the rebel's own view and the former lord's own.
  # Story 919 (criterion 7754) grows the negotiated-peace affordance
  # inline: a pending offer's own Accept/Reject (only for whichever
  # side did NOT make the offer), or a fresh Offer Peace form while the
  # war is still active and nothing is pending.
  attr :rebellion, :map, required: true
  attr :viewer_user_id, :integer, required: true

  defp rebellion_panel(assigns) do
    ~H"""
    <div
      data-test="rebellion-panel"
      class="flex flex-col gap-1 text-xs border border-base-300 rounded-box p-2"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="font-semibold">
          <span data-test="rebellion-rebel">{@rebellion.rebel_name}</span>
          vs <span data-test="rebellion-former-lord">{@rebellion.former_lord_name}</span>
        </span>
        <span class="badge badge-outline badge-sm" data-test="rebellion-status">
          {@rebellion.status}
        </span>
      </div>

      <div class="flex items-center gap-2 opacity-70">
        <span>Turn <span data-test="rebellion-started-turn">{@rebellion.started_turn}</span></span>
        <span>Army <span data-test="rebellion-army-size">{@rebellion.army_size}</span></span>
        <span>
          Risen <span data-test="rebellion-risen-cities">{length(@rebellion.risen_city_ids)}</span>
        </span>
        <span>
          Contested
          <span data-test="rebellion-contested-cities">{length(@rebellion.loyal_city_ids)}</span>
        </span>
      </div>

      <div
        :if={@rebellion.pending_peace_offer}
        class="flex flex-col gap-1"
        data-test="pending-peace-offer"
      >
        <span>
          {@rebellion.pending_peace_offer.offered_by_name} offers peace: {peace_outcome_label(
            @rebellion.pending_peace_offer.outcome
          )}
          <span :if={@rebellion.pending_peace_offer.reparations_gold}>
            ({@rebellion.pending_peace_offer.reparations_gold} gold reparations)
          </span>
        </span>
        <div
          :if={@rebellion.pending_peace_offer.offered_by_user_id != @viewer_user_id}
          class="flex gap-1"
        >
          <button
            type="button"
            phx-click="accept_peace"
            phx-value-counterparty_user_id={@rebellion.pending_peace_offer.offered_by_user_id}
            data-test="accept-peace"
            class="btn btn-xs btn-primary"
          >
            Accept
          </button>
          <button
            type="button"
            phx-click="reject_peace"
            phx-value-counterparty_user_id={@rebellion.pending_peace_offer.offered_by_user_id}
            data-test="reject-peace"
            class="btn btn-xs btn-outline"
          >
            Reject
          </button>
        </div>
      </div>

      <form
        :if={@rebellion.status == :active and is_nil(@rebellion.pending_peace_offer)}
        phx-submit="offer_peace"
        class="flex items-center gap-1"
        data-test={"offer-peace-form-#{@rebellion.id}"}
      >
        <input
          type="hidden"
          name="counterparty_user_id"
          value={rebellion_counterparty_user_id(@rebellion, @viewer_user_id)}
        />
        <select name="outcome" class="select select-xs">
          <option value="independence">Grant independence</option>
          <option value="restored_vassal">Restore as vassal</option>
        </select>
        <input
          type="number"
          name="reparations_gold"
          min="0"
          placeholder="gold"
          class="input input-xs w-16"
        />
        <button type="submit" data-test="offer-peace" class="btn btn-xs btn-outline">
          Offer Peace
        </button>
      </form>
    </div>
    """
  end

  defp rebellion_counterparty_user_id(rebellion, viewer_user_id) do
    if viewer_user_id == rebellion.rebel_user_id,
      do: rebellion.former_lord_user_id,
      else: rebellion.rebel_user_id
  end

  defp peace_outcome_label(:independence), do: "full independence"
  defp peace_outcome_label(:restored_vassal), do: "restored vassalage"

  # The lord's own "Vassals" list — a dropdown so it never crowds the
  # top bar; only mounted at all while `@vassals` is non-empty
  # (`BrokenOathsSpex.Story907.Criterion7667Spex`'s own anchor: no
  # `vassals-list` element exists at all for a lord with zero vassals).
  attr :vassals, :list, required: true
  attr :known_players, :list, required: true

  defp vassals_panel(assigns) do
    ~H"""
    <div data-test="vassals-list" class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-sm btn-outline gap-1">
        <.icon name="hero-users" class="w-3 h-3" /> Vassals ({length(@vassals)})
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-10 menu p-3 shadow bg-base-100 rounded-box w-80 gap-3"
      >
        <.vassal_row :for={vassal <- @vassals} vassal={vassal} known_players={@known_players} />
      </div>
    </div>
    """
  end

  attr :vassal, :map, required: true
  attr :known_players, :list, required: true

  defp vassal_row(assigns) do
    assigns = assign(assigns, :levy_targets, levy_targets(assigns.known_players, assigns.vassal))

    ~H"""
    <div
      data-test={"vassal-row-#{@vassal.vassal_user_id}"}
      class="flex flex-col gap-1 border-b border-base-300 pb-2 last:border-b-0"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm">{@vassal.display_name}</span>
        <span class="badge badge-outline badge-sm" data-test="vassal-tribute-rate">
          {tribute_rate_label(@vassal.tribute_rate)}
        </span>
      </div>

      <div class="flex items-center justify-between text-xs opacity-70">
        <span>Oath Strain <span data-test="vassal-oath-strain">{@vassal.oath_strain}</span></span>
        <span :if={@vassal.levy_status} data-test="levy-status">{@vassal.levy_status}</span>
      </div>

      <%!-- Story 913 (criterion 7721): the strain gauge's own drivers
           breakdown — a narrow tooltip-style surface naming the
           tribute rate as a contributor, the Three Amigos notes' own
           open "how is the gauge surfaced" question resolved to the
           narrowest literal reading of the scenario's own words. --%>
      <div class="text-xs opacity-50" data-test="oath-strain-drivers">
        Driven by tribute rate: {tribute_rate_label(@vassal.tribute_rate)}
      </div>

      <%!-- Story 914: an active Protection Pact call raised against
           THIS vassal — only rendered while one is active, mirroring
           `levy-status`'s own "no element at all with nothing to show"
           posture above. --%>
      <div :if={@vassal.protection_call} class="text-xs text-error" data-test="protection-call">
        {@vassal.display_name} is under attack — respond within
        <span data-test="protection-window">{@vassal.protection_call.window_remaining}</span>
        turn(s)
      </div>

      <%!-- Story 914 (criterion 7730): a running ledger of calls
           honored for this vassal — always rendered (an empty tally is
           a real, renderable "0", not an absent element), same posture
           `oath-strain-drivers` above already takes. --%>
      <div class="text-xs opacity-50">
        Protection honored:
        <span data-test="protection-honored-count">{@vassal.protection_honored_count}</span>
      </div>

      <div class="flex items-center gap-1">
        <button
          type="button"
          phx-click="gift_vassal"
          phx-value-vassal_user_id={@vassal.vassal_user_id}
          phx-value-gift="warrior"
          data-test="gift-vassal"
          class="btn btn-xs btn-outline"
        >
          Gift
        </button>
        <button
          :if={@levy_targets != []}
          type="button"
          phx-click="declare_shared_enemy"
          phx-value-vassal_user_id={@vassal.vassal_user_id}
          phx-value-enemy_user_id={hd(@levy_targets).user_id}
          data-test="declare-shared-enemy"
          class="btn btn-xs btn-outline"
        >
          Shared Enemy
        </button>
        <%!-- Story 916, criterion 7742 — a TARGETED concession, alongside
             the real `set_tribute_rate` form just below: eases this
             ONE vassal's own Oath Strain, honoring an overdue
             Protection Pact call. --%>
        <button
          type="button"
          phx-click="honor_protection_call"
          phx-value-vassal_user_id={@vassal.vassal_user_id}
          data-test="honor-protection-call"
          class="btn btn-xs btn-outline"
        >
          Honor Protection Call
        </button>
      </div>

      <form phx-submit="set_tribute_rate" class="flex items-center gap-1">
        <input type="hidden" name="vassal_user_id" value={@vassal.vassal_user_id} />
        <input
          type="number"
          name="rate"
          min="0"
          max="100"
          value={round(@vassal.tribute_rate * 100)}
          class="input input-xs input-bordered w-16"
        />
        <span class="text-xs">%</span>
        <button type="submit" class="btn btn-xs">Set Rate</button>
      </form>

      <%!-- QA issue dae2e65d — the lord's own "issue a call to arms"
           control: pick a third-party target (never the vassal
           themselves — `@levy_targets` already excludes them, mirroring
           `Levy`'s own `validate_target_not_vassal` guard) and a
           pledged share, wired to the existing `"issue_levy"` handler.
           Only rendered while there's an actual legal target known
           (`@levy_targets != []`) — an empty `<select>` would only ever
           be refused server-side anyway. --%>
      <form
        :if={@levy_targets != []}
        phx-submit="issue_levy"
        class="flex flex-col gap-1"
        data-test={"issue-levy-form-#{@vassal.vassal_user_id}"}
      >
        <input type="hidden" name="vassal_user_id" value={@vassal.vassal_user_id} />
        <div class="flex items-center gap-1">
          <select name="target_user_id" class="select select-xs select-bordered flex-1">
            <option :for={target <- @levy_targets} value={target.user_id}>{target.display_name}</option>
          </select>
          <input
            type="number"
            name="share"
            min="0.1"
            max="1"
            step="0.1"
            value="0.5"
            class="input input-xs input-bordered w-16"
          />
        </div>
        <button type="submit" data-test="issue-levy" class="btn btn-xs btn-outline self-start">
          Call to Arms
        </button>
      </form>

      <%!-- Story 910: stewarding an OFFLINE vassal's bank — a lord may
           always steward their own vassal (`Stewardship.steward_role/4`
           always resolves `:lord` here), so this only ever hides on
           `online?`, never on eligibility. --%>
      <button
        :if={!@vassal.online?}
        type="button"
        phx-click="steward_collect_bank"
        phx-value-owner_user_id={@vassal.vassal_user_id}
        data-test="steward-collect-bank"
        class="btn btn-xs btn-outline self-start"
      >
        Steward: Collect Bank
      </button>

      <%!-- QA issue bd93cc0a: production stewardship — set this
           OFFLINE vassal's own production queue from the
           CONSTRUCTIVE-only whitelist (`Stewardship.
           constructive_item?/1`, already filtered server-side into
           `@vassal.steward.cities`'s own `catalog`). One compact form
           PER city rather than a single cross-city dropdown pair — two
           cities can offer different catalogs (research/Copper access
           differ per city), and a shared `<select>` pair would need its
           own JS to keep the item options in sync with whichever city
           is picked. --%>
      <div :for={city <- steward_cities_with_catalog(@vassal.steward)} class="flex flex-col gap-1">
        <span class="text-xs opacity-70">{city.name}</span>
        <form
          phx-submit="steward_queue_production"
          data-test={"steward-production-#{city.id}"}
          class="flex items-center gap-1"
        >
          <input type="hidden" name="owner_user_id" value={@vassal.vassal_user_id} />
          <input type="hidden" name="city_id" value={city.id} />
          <select name="item" class="select select-xs select-bordered flex-1">
            <option :for={type <- city.catalog} value={type}>{steward_item_label(type)}</option>
          </select>
          <button
            type="submit"
            data-test={"steward-queue-production-#{city.id}"}
            class="btn btn-xs btn-outline"
          >
            Steward: Set Production
          </button>
        </form>
      </div>

      <%!-- QA issue bd93cc0a: emergency defense — only ever offered
           while this OFFLINE vassal is genuinely `Stewardship.
           under_attack?/1`; each button issues a strictly adjacent
           `"steward_defend"` order (`Stewardship.
           defend_target_allowed?/3`'s own gate) for one of their own
           threatened units. --%>
      <div
        :if={
          @vassal.steward && @vassal.steward.under_attack? &&
            @vassal.steward.threatened_units != []
        }
        data-test={"steward-defend-#{@vassal.vassal_user_id}"}
        class="flex flex-col gap-1"
      >
        <span class="text-xs text-error font-medium">Under attack!</span>
        <.steward_defend_unit
          :for={unit <- @vassal.steward.threatened_units}
          unit={unit}
          owner_user_id={@vassal.vassal_user_id}
        />
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Steward controls (QA issue bd93cc0a) — shared between `vassal_row`
  # above and `GameLive.AlliancePanel`'s own `alliance_row` (a plain
  # markup duplication, same status "Steward: Collect Bank" already
  # has across the two modules — see that button's own moduledoc note
  # for why alliance stewardship bubbles straight to `Play` with no
  # `phx-target` instead of routing through the component).
  # -------------------------------------------------------------------

  # Only offer a city's own production form once it actually HAS a
  # non-empty constructive catalog to offer — a size-1, freshly founded
  # city with no research yet still has `[:settler, :worker, :warrior]`
  # (the always-available baseline), so in practice this only ever
  # excludes `nil` (the vassal is online, nothing to steward).
  defp steward_cities_with_catalog(nil), do: []

  defp steward_cities_with_catalog(steward),
    do: Enum.filter(steward.cities, &(&1.catalog != []))

  attr :unit, :map, required: true
  attr :owner_user_id, :any, required: true

  defp steward_defend_unit(assigns) do
    ~H"""
    <div data-test={"steward-unit-#{@unit.id}"} class="flex flex-col gap-1">
      <span class="text-xs">
        {steward_unit_label(@unit.type)} ({@unit.hp}/{@unit.max_hp})
      </span>
      <div class="flex flex-wrap gap-1">
        <button
          :for={tile_id <- @unit.adjacent_tile_ids}
          type="button"
          phx-click="steward_defend"
          phx-value-owner_user_id={@owner_user_id}
          phx-value-unit_id={@unit.id}
          phx-value-to_tile={tile_id}
          data-test={"steward-defend-#{@unit.id}-#{tile_id}"}
          class="btn btn-xs btn-error btn-outline"
        >
          Defend → Tile {tile_id}
        </button>
      </div>
    </div>
    """
  end

  defp steward_item_label(:settler), do: "Settler"
  defp steward_item_label(:worker), do: "Worker"
  defp steward_item_label(:warrior), do: "Warrior"
  defp steward_item_label(:granary), do: "Granary"
  defp steward_item_label(:bronze_spearman), do: "Bronze Spearman"
  defp steward_item_label(type), do: type |> to_string() |> String.capitalize()

  defp steward_unit_label(:lord), do: "Lord"
  defp steward_unit_label(:settler), do: "Settler"
  defp steward_unit_label(:worker), do: "Worker"
  defp steward_unit_label(:warrior), do: "Warrior"
  defp steward_unit_label(:bronze_spearman), do: "Bronze Spearman"
  defp steward_unit_label(type), do: type |> to_string() |> String.capitalize()

  # QA issue dae2e65d — legal call-to-arms targets for `vassal`: every
  # known civilization EXCEPT the vassal themselves (`Levy`'s own
  # `validate_target_not_vassal`/`validate_target_not_lord` schema
  # guards already refuse both server-side; this just keeps the
  # dropdown from ever offering an option that would only bounce).
  defp levy_targets(known_players, vassal),
    do: Enum.reject(known_players, &(&1.user_id == vassal.vassal_user_id))

  # -------------------------------------------------------------------
  # Captured Cities (QA issue ffa66192 — the execute/release UI)
  # -------------------------------------------------------------------

  # The conqueror's own tracker for cities they've personally captured
  # — a dropdown, same "never crowd the top bar" reasoning
  # `vassals_panel` above already uses; only mounted while non-empty
  # (`Play`'s own render gates on `@captured_cities != []`).
  attr :captured_cities, :list, required: true

  defp captured_cities_panel(assigns) do
    ~H"""
    <div data-test="captured-cities-panel" class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-sm btn-outline btn-warning gap-1">
        <.icon name="hero-flag" class="w-3 h-3" /> Captured ({length(@captured_cities)})
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-10 menu p-3 shadow bg-base-100 rounded-box w-72 gap-2"
      >
        <.captured_city_row :for={city <- @captured_cities} city={city} />
      </div>
    </div>
    """
  end

  attr :city, :map, required: true

  defp captured_city_row(assigns) do
    ~H"""
    <div
      data-test={"captured-city-#{@city.id}"}
      class="flex flex-col gap-1 border-b border-base-300 pb-2 last:border-b-0"
    >
      <span class="text-sm font-medium">{@city.name}</span>

      <div :if={@city.fallen_garrison?} class="flex flex-col gap-1" data-test="fallen-garrison-choice">
        <span class="text-xs opacity-70">A fallen garrison awaits your judgment.</span>
        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click="resolve_garrison_fate"
            phx-value-city_id={@city.id}
            phx-value-choice="release"
            data-test={"release-garrison-#{@city.id}"}
            class="btn btn-xs btn-outline"
          >
            Release
          </button>
          <button
            type="button"
            phx-click="resolve_garrison_fate"
            phx-value-city_id={@city.id}
            phx-value-choice="execute"
            data-test={"execute-garrison-#{@city.id}"}
            class="btn btn-xs btn-error"
          >
            Execute
          </button>
        </div>
      </div>

      <span :if={!@city.fallen_garrison?} class="text-xs opacity-60">
        Secured — no living defenders remain.
      </span>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Steward log (story 910)
  # -------------------------------------------------------------------

  attr :steward_log, :list, required: true

  defp steward_log_panel(assigns) do
    ~H"""
    <div data-test="steward-log" class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-sm btn-ghost gap-1">
        <.icon name="hero-clipboard-document-list" class="w-3 h-3" />
        Steward Log ({length(@steward_log)})
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-10 menu p-3 shadow bg-base-100 rounded-box w-80 gap-1"
      >
        <p :if={@steward_log == []} class="text-xs opacity-60">
          No steward actions taken on your behalf yet.
        </p>
        <div
          :for={entry <- @steward_log}
          data-test="steward-log-entry"
          class="flex items-center justify-between gap-2 text-xs border-b border-base-300 pb-1 last:border-b-0"
        >
          <span class="truncate">{entry.steward_name}</span>
          <span class="opacity-70">{entry.action}</span>
          <span :if={entry.sabotage} class="badge badge-error badge-xs">sabotage</span>
        </div>
      </div>
    </div>
    """
  end

  defp tribute_rate_label(rate), do: "#{round(rate * 100)}%"

  # Story 916, criterion 7738 — every OTHER pact member's own `status`
  # already arrives pre-masked to `:invited` from `Game.pact_view/2`;
  # this only ever turns that (already-secret-safe) atom into copy.
  defp pact_status_label(:invited), do: "Outstanding"
  defp pact_status_label(:committed), do: "Committed"
  defp pact_status_label(:declined), do: "Declined"
end
