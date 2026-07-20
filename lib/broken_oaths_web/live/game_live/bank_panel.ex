defmodule BrokenOathsWeb.GameLive.BankPanel do
  @moduledoc """
  The Gold Bank badges (story 909): current holdings vs. cap, a
  Collect button (sweeps the bank into the treasury), and an Upgrade
  button (raises the cap for a gold cost).

  A presentational component mounted unconditionally by
  `BrokenOathsWeb.GameLive.Play`, which owns pulling `:bank` and
  refreshing it after every collect/upgrade — same "presentational,
  reads render straight off whatever `Play` hands it, never calls
  `BrokenOaths.Game` itself, defines no `handle_event/3` of its own"
  status `GameLive.AgePanel`/`GameLive.CityPanel` already have. Every
  button here pushes a plain `phx-click` with no `phx-target`, so it
  bubbles straight to `Play` — the SAME `"collect_bank"`/`"upgrade_bank"`
  events story 909's own BDD spex drive directly against `Play`'s own
  `handle_event/3` (there is no `handle_event/3` clause on THIS module
  at all, so a `phx-target` here would simply crash the click).

  Assigns (from `Play`):

    * `:id` - the DOM id for this component instance
    * `:bank` - `%{gold:, cap:}` (`BrokenOaths.Feudal.Bank.status/1`) —
      `:bank-gold`/`:bank-cap`'s own two badges
    * `:error` - `nil`, or a short string from a refused
      `"upgrade_bank"` attempt (an empty treasury) — cleared the next
      time either button succeeds
  """

  use BrokenOathsWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex items-center gap-1">
      <span class="badge badge-neutral gap-1" title="Bank">
        <.icon name="hero-building-library" class="w-3 h-3" />
        <span data-test="bank-gold">{@bank.gold}</span>
        <span class="opacity-60">/</span>
        <span data-test="bank-cap">{@bank.cap}</span>
      </span>

      <button
        type="button"
        phx-click="collect_bank"
        data-test="collect-bank"
        class="btn btn-ghost btn-xs"
        title="Sweep the bank into your treasury"
      >
        Collect
      </button>

      <button
        type="button"
        phx-click="upgrade_bank"
        data-test="upgrade-bank"
        class="btn btn-ghost btn-xs"
        title="Raise your bank's own cap"
      >
        Upgrade
      </button>

      <span :if={@error} data-test="bank-error" class="badge badge-error badge-sm">
        {@error}
      </span>
    </div>
    """
  end
end
