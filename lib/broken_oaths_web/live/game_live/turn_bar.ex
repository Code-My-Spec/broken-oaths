defmodule BrokenOathsWeb.GameLive.TurnBar do
  @moduledoc """
  Displays the current turn number and a countdown to the next turn
  boundary.

  Turn boundaries are wall-clock (60s in production) and server-authoritative
  — this component never advances a turn itself. The parent LiveView is the
  source of truth and supplies it as assigns:

    * `:id` — required, DOM id for the component
    * `:turn` — required, the current turn number (non-negative integer)
    * `:turn_ends_at` — required, the `DateTime` the next boundary fires

  Once mounted, the component re-renders itself once a second (via
  `send_update_after/3`) so the countdown ticks down without the parent
  having to manage a timer. When the parent pushes a new `:turn` /
  `:turn_ends_at` pair (because the boundary fired), the countdown simply
  resets against the new deadline.

  Usage:

      <.live_component
        module={BrokenOathsWeb.GameLive.TurnBar}
        id="turn-bar"
        turn={@turn}
        turn_ends_at={@turn_ends_at}
      />
  """

  use BrokenOathsWeb, :live_component

  @tick_interval_ms 1_000

  @impl true
  def update(%{id: id, turn: turn, turn_ends_at: %DateTime{} = turn_ends_at}, socket)
      when is_integer(turn) and turn >= 0 do
    if connected?(socket), do: schedule_tick(id)

    {:ok,
     socket
     |> assign(id: id, turn: turn, turn_ends_at: turn_ends_at)
     |> assign(:seconds_remaining, seconds_remaining(turn_ends_at))}
  end

  # Self-scheduled tick (see schedule_tick/1): no new truth arrives, just
  # recompute the countdown against the deadline already held in assigns.
  def update(%{id: id}, socket) do
    if connected?(socket), do: schedule_tick(id)

    {:ok, assign(socket, :seconds_remaining, seconds_remaining(socket.assigns.turn_ends_at))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="turn-bar flex items-center gap-3 text-sm font-medium">
      <span class="badge badge-neutral font-mono">
        Turn <span data-test="turn-number">{@turn}</span>
      </span>
      <span class="font-mono tabular-nums" data-test="turn-countdown">{@seconds_remaining}</span>
    </div>
    """
  end

  defp schedule_tick(id), do: send_update_after(__MODULE__, [id: id], @tick_interval_ms)

  defp seconds_remaining(%DateTime{} = turn_ends_at) do
    turn_ends_at
    |> DateTime.diff(DateTime.utc_now())
    |> max(0)
  end
end
