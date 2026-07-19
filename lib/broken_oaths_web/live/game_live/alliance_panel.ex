defmodule BrokenOathsWeb.GameLive.AlliancePanel do
  @moduledoc """
  Propose/accept alliances with known players, and see who this
  player is already allied with (story 901).

  A stateful `LiveComponent`, same shape as `GameLive.ChatPanel`: it
  owns its own open/closed toggle and defines its own `handle_event/3`
  clauses (every one scoped with `phx-target={@myself}`), but every
  actual alliance mutation goes through `BrokenOaths.Game`
  (`alliances/2`, `propose_alliance/3`, `accept_alliance/3` — the
  command surface this component exists to give a UI to; see
  `BrokenOaths.Game.Cooperation`'s propose/accept business rules and
  `BrokenOaths.Game.Alliance`'s schema doc for why an alliance is
  PLAYER-FACING coordination signal, not a precondition for anything
  — cooperative bounty splitting on a shared barbarian kill never
  checks for one, criterion 7624).

  Mounted unconditionally by `BrokenOathsWeb.GameLive.Play`, alongside
  `GameLive.ChatPanel`:

      <.live_component
        module={BrokenOathsWeb.GameLive.AlliancePanel}
        id="alliance-panel"
        world={@world}
        user={@user}
        known_players={@known_players}
      />

  Assigns (from `Play`):

    * `:id` - required, DOM id for this component instance
    * `:world` - the `BrokenOaths.Worlds.World` alliances are scoped to
    * `:user` - the viewing player's `BrokenOaths.Users.User`
    * `:known_players` - `[%{user_id:, email:}]`, `Play`'s own
      `Game.known_players/2` read (story 899) — who's even eligible to
      propose an alliance with. `Chat.list_conversations/2`
      independently re-derives the same fact for `ChatPanel`'s own
      contact list; this component takes it as a plain assign instead
      since (unlike chat) alliance proposal has no other reason to
      touch `BrokenOaths.Chat`.

  Deliberately DISTINCT `data-test` naming from `GameLive.
  KnownPlayersPanel`/`GameLive.ChatPanel`'s own `"known-player-ID"`
  rows (`"ally-candidate-ID"` for a proposable contact,
  `"alliance-ID"` for an existing alliance row) — this panel renders
  alongside both of those (no "one side panel at a time" exclusion
  the way `ChatPanel` needs against `KnownPlayersPanel`), so reusing
  their selector would make `element/2` + `render_click/1` ambiguous
  the moment both are on the page — see `ChatPanel`'s own moduledoc
  for the collision this same discipline avoids there.

  ## Real-time delivery

  `Play`'s own `handle_info(:alliances_changed, socket)` (fired by
  `WorldServer` after every successful propose/accept, world-wide,
  same broadcast shape as `:cities_changed`) forwards straight into
  this component via `send_update(__MODULE__, id: "alliance-panel",
  refresh: true)` — so the OTHER party to a proposal sees it appear
  live, without waiting on their next turn-boundary refresh, the same
  "component has no mailbox of its own, the parent forwards" pattern
  `ChatPanel` already establishes for `{:chat_message, message}`.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Game
  alias BrokenOaths.Users

  @impl true
  def update(%{refresh: true}, socket) do
    {:ok, refresh_alliances(socket)}
  end

  def update(%{id: id, world: world, user: user} = assigns, socket) do
    known_players = Map.get(assigns, :known_players, [])

    socket =
      socket
      |> assign(id: id, world: world, user: user, known_players: known_players)
      |> assign_new(:open?, fn -> false end)
      |> assign_new(:error, fn -> nil end)
      |> refresh_alliances()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_alliance_panel", _params, socket) do
    {:noreply, assign(socket, open?: !socket.assigns.open?)}
  end

  def handle_event("propose_alliance", %{"user_id" => user_id}, socket) do
    %{world: world, user: user} = socket.assigns
    other_user = Users.get_user!(parse_id(user_id))

    case Game.propose_alliance(world, user, other_user) do
      :ok -> {:noreply, socket |> assign(error: nil) |> refresh_alliances()}
      {:error, reason} -> {:noreply, assign(socket, error: alliance_error_message(reason))}
    end
  end

  def handle_event("accept_alliance", %{"alliance_id" => alliance_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.accept_alliance(world, user, parse_id(alliance_id)) do
      :ok -> {:noreply, socket |> assign(error: nil) |> refresh_alliances()}
      {:error, reason} -> {:noreply, assign(socket, error: alliance_error_message(reason))}
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp refresh_alliances(socket) do
    %{world: world, user: user} = socket.assigns
    assign(socket, alliances: Game.alliances(world, user))
  end

  # Known players not already the other side of a proposed/accepted
  # alliance row — the roster this panel offers a "Propose" button for.
  defp proposable(known_players, alliances) do
    allied_ids = MapSet.new(alliances, & &1.other_user_id)
    Enum.reject(known_players, &MapSet.member?(allied_ids, &1.user_id))
  end

  defp alliance_error_message(:not_a_player), do: "That player hasn't joined this world."
  defp alliance_error_message(:already_proposed), do: "An alliance with them is already pending."
  defp alliance_error_message(:already_allied), do: "You're already allied with them."
  defp alliance_error_message(:not_found), do: "That alliance no longer exists."
  defp alliance_error_message(:not_a_party), do: "That alliance isn't yours to accept."
  defp alliance_error_message(:self_accept), do: "You can't accept your own proposal."
  defp alliance_error_message(:already_accepted), do: "That alliance is already accepted."
  defp alliance_error_message(%Ecto.Changeset{}), do: "That alliance action failed."

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :proposable, proposable(assigns.known_players, assigns.alliances))

    ~H"""
    <div id={@id} class="relative">
      <button
        type="button"
        data-test="alliance-button"
        phx-click="toggle_alliance_panel"
        phx-target={@myself}
        class="btn btn-sm btn-ghost gap-1"
      >
        <.icon name="hero-shield-check" class="w-4 h-4" />
      </button>

      <div
        :if={@open?}
        data-test="alliance-panel"
        class="card bg-base-200 shadow-xl w-80 absolute top-full right-0 mt-1 z-10"
      >
        <div class="card-body p-3 gap-2">
          <h3 class="card-title text-sm">Alliances</h3>

          <div :if={@error} data-test="alliance-error" class="alert alert-error p-2 text-xs">
            {@error}
          </div>

          <div class="divider my-0 text-xs opacity-60">Propose</div>
          <div data-test="alliance-candidates" class="flex flex-col gap-1">
            <p :if={@proposable == []} class="text-xs opacity-60">
              No discovered players left to propose to.
            </p>

            <.candidate_row :for={contact <- @proposable} contact={contact} myself={@myself} />
          </div>

          <div class="divider my-0 text-xs opacity-60">Your Alliances</div>
          <div data-test="alliances" class="flex flex-col gap-1">
            <p :if={@alliances == []} class="text-xs opacity-60">
              No alliances yet.
            </p>

            <.alliance_row :for={alliance <- @alliances} alliance={alliance} myself={@myself} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :contact, :map, required: true
  attr :myself, :any, required: true

  defp candidate_row(assigns) do
    ~H"""
    <div
      data-test={"ally-candidate-#{@contact.user_id}"}
      class="flex items-center justify-between gap-2 text-sm"
    >
      <span class="truncate">{@contact.email}</span>
      <button
        type="button"
        data-test="propose-alliance"
        phx-click="propose_alliance"
        phx-value-user_id={@contact.user_id}
        phx-target={@myself}
        class="btn btn-ghost btn-xs"
      >
        Propose
      </button>
    </div>
    """
  end

  attr :alliance, :map, required: true
  attr :myself, :any, required: true

  defp alliance_row(assigns) do
    ~H"""
    <div
      data-test={"alliance-#{@alliance.id}"}
      class="flex flex-col gap-1"
    >
      <div class="flex items-center justify-between gap-2 text-sm">
        <span class="truncate">{@alliance.other_email}</span>

        <span
          :if={@alliance.status == :accepted}
          data-test="alliance-status-accepted"
          class="badge badge-success badge-sm"
        >
          Allied
        </span>

        <span
          :if={@alliance.status == :proposed and @alliance.proposed_by_me?}
          data-test="alliance-status-pending"
          class="badge badge-ghost badge-sm"
        >
          Awaiting response
        </span>

        <button
          :if={@alliance.status == :proposed and !@alliance.proposed_by_me?}
          type="button"
          data-test="accept-alliance"
          phx-click="accept_alliance"
          phx-value-alliance_id={@alliance.id}
          phx-target={@myself}
          class="btn btn-primary btn-xs"
        >
          Accept
        </button>
      </div>

      <%!-- Story 910: alliance stewardship is SYMMETRIC — either accepted
           party may steward the other while they're offline. Deliberately
           NO `phx-target`: this button bubbles straight to `Play`'s own
           `"steward_collect_bank"` handler (the same event story 910's own
           BDD spex drive directly), never THIS component's own
           `handle_event/3` (which has no clause for it at all). Gated on
           `Game.feudal_enabled?/0` directly — unlike `vassals-list`/
           `vassal-status`, an accepted `Alliance` is story 901's own
           ALREADY-shipped, always-on feature, so this button (unlike
           theirs) would otherwise render for any offline ally regardless
           of the feudal batch's own dormant-in-prod status. --%>
      <button
        :if={@alliance.status == :accepted and !@alliance.online? and Game.feudal_enabled?()}
        type="button"
        phx-click="steward_collect_bank"
        phx-value-owner_user_id={@alliance.other_user_id}
        data-test="steward-collect-bank"
        class="btn btn-xs btn-outline self-start"
      >
        Steward: Collect Bank
      </button>

      <%!-- QA issue bd93cc0a: production stewardship — set this
           OFFLINE ally's own production queue from the
           CONSTRUCTIVE-only whitelist (`Stewardship.
           constructive_item?/1`, already filtered server-side into
           `@alliance.steward.cities`'s own `catalog`). Same "one form
           per city" reasoning `GameLive.Play`'s own `vassal_row`
           carries; same `Game.feudal_enabled?()` gate the Collect Bank
           button above already needs (an accepted `Alliance` is
           story 901's own already-shipped, always-on feature). Every
           event here bubbles straight to `Play` — deliberately no
           `phx-target`, same status the Collect Bank button above
           already has. --%>
      <div :for={city <- steward_production_cities(@alliance)} class="flex flex-col gap-1">
        <span class="text-xs opacity-70">{city.name}</span>
        <form
          phx-submit="steward_queue_production"
          data-test={"steward-production-#{city.id}"}
          class="flex items-center gap-1"
        >
          <input type="hidden" name="owner_user_id" value={@alliance.other_user_id} />
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
           while this OFFLINE ally is genuinely `Stewardship.
           under_attack?/1`; each button issues a strictly adjacent
           `"steward_defend"` order for one of their own threatened
           units. --%>
      <div
        :if={steward_under_attack?(@alliance)}
        data-test={"steward-defend-#{@alliance.other_user_id}"}
        class="flex flex-col gap-1"
      >
        <span class="text-xs text-error font-medium">Under attack!</span>
        <.steward_defend_unit
          :for={unit <- @alliance.steward.threatened_units}
          unit={unit}
          owner_user_id={@alliance.other_user_id}
        />
      </div>
    </div>
    """
  end

  # QA issue bd93cc0a: an accepted `Alliance` is story 901's own
  # already-shipped, always-on feature (unlike `vassals-list`/
  # `vassal-status`), so both helpers re-check `Game.feudal_enabled?()`
  # directly — same belt-and-suspenders gate the Collect Bank button
  # above already needs, so neither steward affordance would otherwise
  # render for an offline ally regardless of the feudal batch's own
  # dormant-in-prod status.
  defp steward_production_cities(%{steward: nil}), do: []

  defp steward_production_cities(alliance) do
    if Game.feudal_enabled?() do
      Enum.filter(alliance.steward.cities, &(&1.catalog != []))
    else
      []
    end
  end

  defp steward_under_attack?(%{steward: nil}), do: false

  defp steward_under_attack?(alliance) do
    Game.feudal_enabled?() and alliance.steward.under_attack? and
      alliance.steward.threatened_units != []
  end

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
end
