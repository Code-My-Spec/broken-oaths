defmodule BrokenOathsWeb.GameLive.Modals do
  @moduledoc """
  Small standalone modals mounted by `BrokenOathsWeb.GameLive.Play`,
  each with no relation to the other beyond "a `modal modal-open`
  overlay `Play` toggles via a plain boolean/derived assign": the
  Abandon World confirmation, and the Oath screen (story 907) raised
  the instant a capture leaves a player with zero free cities. A
  purely presentational function component: `Play` owns every command
  dispatch (`"abandon_cancel"`/`"abandon_confirm"`/
  `"choose_hidden_agenda"`), these only ever render the assigns given.
  """

  use BrokenOathsWeb, :html

  attr :confirm_abandon?, :boolean, required: true

  def abandon_confirm(assigns) do
    ~H"""
    <div :if={@confirm_abandon?} class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg">Abandon this world?</h3>
        <p class="py-4 opacity-70">
          Your civilization will be wiped and your region freed for another player. This cannot be undone.
        </p>
        <div class="modal-action">
          <button phx-click="abandon_cancel" class="btn btn-ghost">Cancel</button>
          <button phx-click="abandon_confirm" class="btn btn-error" data-test="abandon-confirm">
            Abandon Forever
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :vassal_status, :any, required: true

  def oath_screen(assigns) do
    ~H"""
    <%!-- Story 907 — the Oath screen: raised the moment a capture
           leaves this player with zero free cities, closed the instant
           they secretly pick a Hidden Agenda (`choose_hidden_agenda`). --%>
    <div
      :if={@vassal_status && @vassal_status.agenda_pending?}
      class="modal modal-open"
      data-test="oath-screen"
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg">Terms of Oath</h3>
        <p class="py-2 opacity-70">
          Your last free city has fallen. You are sworn to {@vassal_status.lord_email} — but your
          story is far from over. Choose the ambition you'll secretly pursue as a vassal:
        </p>
        <div class="flex flex-col gap-2">
          <button
            :for={{agenda, label} <- oath_agenda_options()}
            type="button"
            phx-click="choose_hidden_agenda"
            phx-value-agenda={agenda}
            data-test={"agenda-option-#{agenda}"}
            class="btn btn-outline justify-start"
          >
            {label}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp oath_agenda_options do
    [
      {"restore", "Restore — reclaim your fallen realm"},
      {"usurp", "Usurp — seize your lord's own throne"},
      {"kingmaker", "Kingmaker — decide who rules"},
      {"merchant_prince", "Merchant Prince — build wealth beyond war"}
    ]
  end
end
