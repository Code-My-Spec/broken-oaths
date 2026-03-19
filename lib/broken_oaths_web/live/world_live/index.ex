defmodule BrokenOathsWeb.WorldLive.Index do
  use BrokenOathsWeb, :live_view
  alias BrokenOaths.Worlds

  def mount(_params, _session, socket) do
    worlds = Worlds.list_worlds()
    {:ok, assign(socket, worlds: worlds, page_title: "Hex Worlds")}
  end

  def handle_event("new_world", _params, socket) do
    seed = :rand.uniform(999_999_999)
    name = Worlds.random_world_name(seed)

    case Worlds.create_world(%{name: name, seed: seed}) do
      {:ok, world} ->
        {:noreply, push_navigate(socket, to: ~p"/worlds/#{world.id}")}

      {:error, _changeset} ->
        # Seed collision (extremely rare), retry with different seed
        new_seed = :rand.uniform(999_999_999)
        {:ok, world} = Worlds.create_world(%{name: Worlds.random_world_name(new_seed), seed: new_seed})
        {:noreply, push_navigate(socket, to: ~p"/worlds/#{world.id}")}
    end
  end

  def handle_event("delete_world", %{"id" => id}, socket) do
    world = Worlds.get_world!(id)
    {:ok, _} = Worlds.delete_world(world)
    {:noreply, assign(socket, worlds: Worlds.list_worlds())}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-8 max-w-5xl">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-bold">Hex Worlds</h1>
        <button phx-click="new_world" class="btn btn-primary">
          <.icon name="hero-plus" class="w-5 h-5" /> New World
        </button>
      </div>

      <div :if={@worlds == []} class="text-center py-20 opacity-50">
        <.icon name="hero-globe-americas" class="w-16 h-16 mx-auto mb-4 opacity-30" />
        <p class="text-lg">No worlds yet. Create one to get started!</p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div :for={world <- @worlds} class="card bg-base-200 shadow-md hover:shadow-lg transition-shadow">
          <div class="card-body">
            <h2 class="card-title">{world.name}</h2>
            <div class="space-y-1 text-sm opacity-70">
              <p>Seed: {world.seed}</p>
              <p>{world.width} × {world.height} hexes</p>
            </div>
            <div class="card-actions justify-end mt-2">
              <.link navigate={~p"/worlds/#{world.id}"} class="btn btn-sm btn-primary">
                View
              </.link>
              <button
                phx-click="delete_world"
                phx-value-id={world.id}
                data-confirm="Delete this world?"
                class="btn btn-sm btn-error btn-outline"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
