defmodule BrokenOathsWeb.GameLive.Join do
  @moduledoc """
  The world picker — enter the game.

  Lists active worlds and lets the signed-in player join one. Joining is a
  single command to `BrokenOaths.Game`: find the world's open region, claim
  it, and spawn the player's civilization. The LiveView holds no game state
  of its own — it renders the picker, sends the command, and redirects to
  the board on success.

  Depends on this contract from `BrokenOaths.Game` (context not yet
  implemented as of this writing):

    * `claimed_region(world, user) :: region | nil` — already a member?
    * `world_full?(world) :: boolean` — any open region left for a new player?
    * `join_world(world, user) :: {:ok, world} | {:error, :world_full} | {:error, :membership_limit}`
      idempotent for an existing member (resumes without re-spawning).
  """

  use BrokenOathsWeb, :live_view

  alias BrokenOaths.Game
  alias BrokenOaths.Worlds

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Play")
     |> assign(:join_error, nil)
     |> assign(:worlds, active_worlds())}
  end

  # Quick Play — the frictionless entry that makes recruiting scale: drop the
  # player into a world with room (Game.quick_join resumes an existing one,
  # joins the oldest open world so players cluster, or creates a fresh world
  # when they're all full). One click from the picker; no need to read the
  # list or understand capacity.
  @impl true
  def handle_event("quick_play", _params, socket) do
    case Game.quick_join(socket.assigns.current_scope.user) do
      {:ok, world} ->
        {:noreply, push_navigate(socket, to: ~p"/play/#{world.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :join_error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("join", %{"world-id" => world_id}, socket) do
    world = Worlds.get_world!(world_id)
    user = socket.assigns.current_scope.user

    case Game.join_world(world, user) do
      {:ok, _world} ->
        {:noreply, push_navigate(socket, to: ~p"/play/#{world.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :join_error, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-8 max-w-3xl">
      <.header>
        Play
        <:subtitle>Join a world to spawn your civilization</:subtitle>
      </.header>

      <p :if={@join_error} data-test="join-error" class="alert alert-error mt-4">
        {@join_error}
      </p>

      <%!-- Quick Play: one click into a world with room, creating a fresh one
           when every world is full. Always available, so a new player never
           hits a dead end even when the list below is empty. --%>
      <div class="mt-6 flex flex-col items-center gap-2">
        <.button
          data-test="quick-play"
          phx-click="quick_play"
          class="btn-primary btn-lg w-full sm:w-auto sm:px-12"
        >
          Quick Play
        </.button>
        <p class="text-sm opacity-60">Jump straight into a world with room to play.</p>
      </div>

      <div :if={@worlds != []} class="divider mt-8 text-sm opacity-50">or pick a world</div>

      <ul :if={@worlds != []} class="menu bg-base-200 rounded-box w-full">
        <.world_row :for={world <- @worlds} world={world} current_user={@current_scope.user} />
      </ul>
    </div>
    """
  end

  defp world_row(assigns) do
    assigns =
      assigns
      |> assign(:member?, member?(assigns.world, assigns.current_user))
      |> assign(:full?, full?(assigns.world))

    ~H"""
    <li>
      <div class="flex items-center justify-between gap-4 py-2">
        <div>
          <div class="font-semibold">{@world.name}</div>
          <div :if={@member?} class="badge badge-primary badge-sm">Your civilization</div>
        </div>

        <.button
          :if={@member? or not @full?}
          data-test={"join-world-#{@world.id}"}
          phx-click="join"
          phx-value-world-id={@world.id}
        >
          {button_label(@member?)}
        </.button>

        <span
          :if={not @member? and @full?}
          data-test={"world-full-#{@world.id}"}
          class="badge badge-ghost"
        >
          Full
        </span>
      </div>
    </li>
    """
  end

  defp button_label(true), do: "Enter"
  defp button_label(false), do: "Join"

  defp error_message(:world_full), do: "That world just filled up — pick another."
  defp error_message(:membership_limit), do: "You can only play in three worlds at once."

  defp member?(world, user), do: Game.claimed_region(world, user) != nil
  defp full?(world), do: Game.world_full?(world)

  defp active_worlds do
    Worlds.list_worlds()
    |> Enum.filter(&(&1.status == "active"))
  end
end
