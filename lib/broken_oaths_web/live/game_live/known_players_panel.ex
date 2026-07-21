defmodule BrokenOathsWeb.GameLive.KnownPlayersPanel do
  @moduledoc """
  Standalone panel listing every civilization the player has discovered
  (story 899): a durable roster, unrelated to current fog of war —
  once a player enters this list they stay on it, even after leaving
  sight or logging off (`BrokenOaths.Diplomacy.KnownPlayer`, permanent once
  recorded).

  A presentational component mounted by `BrokenOathsWeb.GameLive.Play`,
  which owns the actual discovery state (`BrokenOaths.Game.
  known_players/2`) and re-pulls it on every `:units_changed`/
  `:turn_advanced` refresh — this component never reads from
  `BrokenOaths.Game` itself and defines no `handle_event/3` of its own.
  Every interactive element pushes a plain DOM event with no
  `phx-target`, so it bubbles to `Play` exactly like `GameLive.
  CityPanel`/`GameLive.UnitPanel`'s pattern — no component-owned state.
  `chat-link` pushes `"open_chat"`; the row itself (playtest issue 4)
  pushes `"center_on_player"` with `phx-value-user_id`, which `Play`
  resolves into a fog-respecting camera move (`Game.visible_tile_of/3`)
  rather than anything this component computes.

  The discovery TOAST half of this component's job (story 899,
  criterion 7617 — "flashed and logged") is already handled by `Play`
  itself: `Play.handle_info({:discovery, user_id, message}, socket)`
  pushes `"game:discovery"` straight to the client the instant
  `BrokenOaths.Diplomacy.Discovery` fires, independent of whether this panel
  is even mounted. This component owns only the durable, "logged" half
  — the roster.

  Assigns:

    * `:id` - the DOM id for this component instance
    * `:known_players` - `[%{user_id:, display_name:}]`, every
      civilization `Play`'s own player has discovered in this world
      (`Game.known_players/2`). `display_name` is the player-facing
      handle, never the email (playtest issue 2a9df843) — `[]` before any
      discovery has happened, which renders the panel's empty state

  `Play` hides this panel while `GameLive.ChatPanel` is open (its own
  contact list reuses the same `known-player-ID` row shape story 900's
  surface contract calls for) — the same "one side panel at a time"
  discipline `Play`'s moduledoc already documents for unit/city
  selection, so a `known-player-ID` selector never matches more than
  one element at once.
  """

  use BrokenOathsWeb, :live_component

  def render(assigns) do
    ~H"""
    <div id={@id} data-test="known-players-panel" class="card bg-base-200 shadow-sm w-64">
      <div class="card-body gap-2 p-3">
        <h3 class="card-title text-sm">Known Players</h3>

        <p
          :if={@known_players == []}
          data-test="known-players-empty"
          class="text-xs opacity-60"
        >
          No other civilizations discovered yet.
        </p>

        <.known_player :for={player <- @known_players} player={player} />
      </div>
    </div>
    """
  end

  attr :player, :map, required: true

  defp known_player(assigns) do
    ~H"""
    <div
      data-test={"known-player-#{@player.user_id}"}
      phx-click="center_on_player"
      phx-value-user_id={@player.user_id}
      class="flex items-center justify-between gap-2 text-sm cursor-pointer"
    >
      <span class="truncate">{@player.display_name}</span>
      <button
        type="button"
        data-test="chat-link"
        phx-click="open_chat"
        phx-value-user_id={@player.user_id}
        class="btn btn-ghost btn-xs"
        aria-label={"Chat with #{@player.display_name}"}
      >
        <.icon name="hero-chat-bubble-left-right" class="w-3 h-3" />
      </button>
    </div>
    """
  end
end
