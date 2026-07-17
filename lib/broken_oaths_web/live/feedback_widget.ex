defmodule BrokenOathsWeb.FeedbackWidget do
  @moduledoc """
  Floating feedback widget for reporting issues to CodeMySpec.

  Submissions authenticate with the app's deploy key, so any logged-in
  user can send feedback — no per-user CodeMySpec connection required.
  Renders nothing when logged out or when no deploy key is configured.
  No hooks, no prop-drilling, no layout attr changes needed.

  ## Usage

  Add to Layouts.app (current_scope is already passed):

      <.live_component
        module={BrokenOathsWeb.FeedbackWidget}
        id="codemyspec-feedback"
        current_scope={@current_scope}
      />
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Codemyspec.Client

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if connected?(socket) && !Map.has_key?(socket.assigns, :enabled) do
        enabled = socket.assigns[:current_scope] != nil && Client.enabled?()

        socket
        |> assign(:enabled, enabled)
        |> assign(:expanded, false)
        |> assign(:submitted, false)
        |> assign(:error, nil)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, expanded: !socket.assigns.expanded, submitted: false, error: nil)}
  end

  @impl true
  def handle_event("submit_feedback", params, socket) do
    title = String.trim(params["title"] || "")
    description = String.trim(params["description"] || "")
    severity = params["severity"] || "medium"

    if title == "" do
      {:noreply, assign(socket, :error, "Title is required")}
    else
      user = socket.assigns.current_scope.user

      attrs = %{
        "title" => title,
        "description" => "#{description}\n\nReported by: #{user.email}",
        "severity" => severity
      }

      case Client.create_issue(attrs) do
        {:ok, _} ->
          {:noreply, socket |> assign(:submitted, true) |> assign(:error, nil)}

        {:error, reason} ->
          {:noreply, assign(socket, :error, "Failed to submit: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if Map.get(assigns, :enabled, false) do %>
        <div class="fixed bottom-4 right-4 z-50" id="cms-feedback">
          <%= if @expanded do %>
            <div class="card bg-base-100 shadow-2xl border border-base-300 w-80">
              <div class="card-body p-4">
                <div class="flex items-center justify-between mb-2">
                  <h3 class="card-title text-sm">Send Feedback</h3>
                  <button
                    phx-click="toggle"
                    phx-target={@myself}
                    class="btn btn-ghost btn-xs btn-circle"
                  >
                    &times;
                  </button>
                </div>

                <%= if @submitted do %>
                  <div class="text-center py-4">
                    <div class="text-success text-lg mb-2">&#10003;</div>
                    <p class="text-sm text-base-content/70">Thanks for your feedback!</p>
                    <button phx-click="toggle" phx-target={@myself} class="btn btn-ghost btn-sm mt-2">
                      Close
                    </button>
                  </div>
                <% else %>
                  <form phx-submit="submit_feedback" phx-target={@myself} class="space-y-3">
                    <%= if @error do %>
                      <div class="alert alert-error text-xs p-2"><span>{@error}</span></div>
                    <% end %>

                    <input
                      type="text"
                      name="title"
                      placeholder="Brief summary"
                      required
                      class="input input-bordered input-sm w-full"
                    />
                    <textarea
                      name="description"
                      placeholder="Describe the issue..."
                      rows="3"
                      class="textarea textarea-bordered textarea-sm w-full"
                    ></textarea>
                    <select name="severity" class="select select-bordered select-sm w-full">
                      <option value="low">Low</option>
                      <option value="medium" selected>Medium</option>
                      <option value="high">High</option>
                      <option value="critical">Critical</option>
                    </select>
                    <button type="submit" class="btn btn-primary btn-sm w-full">
                      Submit Feedback
                    </button>
                  </form>
                <% end %>
              </div>
            </div>
          <% else %>
            <button
              phx-click="toggle"
              phx-target={@myself}
              class="btn btn-primary btn-circle shadow-lg"
              title="Send feedback"
            >
              <svg
                width="20"
                height="20"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                />
              </svg>
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
