defmodule BrokenOathsWeb.WorldLive.New do
  @moduledoc """
  World-creation form (story 905): a name and the per-world resource-
  density picker (`:sparse | :standard | :dense`,
  `BrokenOaths.Worlds.World.resource_density`), mirroring
  `WorldLive.Index`'s own create-and-redirect idiom — but as its own
  route/page rather than an inline button, since density is now a real
  choice instead of always defaulting silently.

  Route: `GET /worlds/new`. On success, redirects straight to the new
  world's show page, exactly like `WorldLive.Index`'s own `new_world`
  handler.
  """

  use BrokenOathsWeb, :live_view

  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.World

  @densities [Sparse: "sparse", Standard: "standard", Dense: "dense"]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-8 max-w-lg">
      <.header>New Hex World</.header>

      <.form for={@form} id="new-world-form" data-test="new-world-form" phx-submit="create_world">
        <.input field={@form[:name]} type="text" label="World name" required />
        <.input
          field={@form[:resource_density]}
          type="select"
          label="Resource density"
          options={@densities}
          data-test="resource-density-slider"
        />
        <div class="flex justify-end mt-4">
          <.button phx-disable-with="Creating..." class="btn btn-primary">
            Create World
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    changeset = World.creation_changeset(%World{}, %{})

    {:ok,
     socket
     |> assign(page_title: "New Hex World", densities: @densities)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("create_world", %{"world" => world_params}, socket) do
    {:noreply, create_world(socket, world_params, random_seed())}
  end

  # A seed collision retries once with a fresh seed — the same
  # tolerance `WorldLive.Index`'s own `new_world` handler already
  # gives `unique_constraint(:seed)` (astronomically rare, but not
  # impossible). Any OTHER error (e.g. a blank name) is a real
  # validation failure the form should show, not silently retried.
  defp create_world(socket, world_params, seed) do
    case Worlds.create_world(Map.put(world_params, "seed", seed)) do
      {:ok, world} ->
        push_navigate(socket, to: ~p"/worlds/#{world.id}")

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :seed) do
          create_world(socket, world_params, random_seed())
        else
          assign_form(socket, changeset)
        end
    end
  end

  defp random_seed, do: :rand.uniform(999_999_999)

  defp assign_form(socket, %Ecto.Changeset{} = changeset),
    do: assign(socket, form: to_form(changeset, as: "world"))
end
