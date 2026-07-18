defmodule BrokenOathsWeb.GameLive.UnitPanel do
  @moduledoc """
  Selected unit details (type, HP, movement remaining), its queued
  order, and its city-loop actions: Found City for a settler, Build
  Improvement for a worker.

  A presentational component mounted by `BrokenOathsWeb.GameLive.Play`,
  which owns unit selection, order state, and command dispatch — every
  button here pushes a plain event with no `phx-target`, so it bubbles
  to `Play` exactly like unit selection already does. This component
  never reads from `BrokenOaths.Game` itself — it only renders the
  assigns it's given:

    * `:id` - the DOM id for this component instance
    * `:unit` - the selected unit, or `nil` when nothing is selected.
      Expected to carry `:id`, `:type` (`:lord` | `:settler` | `:worker`
      | `:warrior` | `:barbarian_warrior` | `:bronze_spearman`), `:hp`,
      `:max_hp`, `:movement`, `:max_movement`
    * `:order` - the unit's queued order, or `nil`. Expected to carry
      `:target_tile` and `:status` (`:pending` | `:interrupted`)
    * `:allowed_improvements` - improvement kinds (`:farm` | `:mine` |
      `:road` | `:pasture`) legal on the worker's own tile right now —
      `Play` computes this (it needs world/terrain/resource access this
      component doesn't have) so only legal Build actions ever render
      (story 882, criterion 7482: Farm is never offered on hills/
      forest; story 905, criterion 7648: Pasture only once Animal
      Husbandry is researched, and only on a Cattle/Sheep tile)
  """

  use BrokenOathsWeb, :live_component

  def render(%{unit: nil} = assigns) do
    ~H"""
    <div id={@id}></div>
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:allowed_improvements, fn -> [] end)
      |> assign_new(:current_dig, fn -> nil end)
      |> assign_new(:unit_id, fn -> Map.get(assigns.unit, :id) end)

    ~H"""
    <div id={@id} data-test="unit-panel" class="card bg-base-200 shadow-sm">
      <div class="card-body gap-2">
        <h3 data-test="unit-type" class="card-title text-base">
          {unit_type_label(@unit.type)}
          <span :if={@unit.type == :lord} data-test="unit-crown">
            <.icon name="hero-trophy-solid" class="size-4 text-warning" />
          </span>
        </h3>
        <p data-test="unit-hp" class="text-sm">
          HP {@unit.hp}/{@unit.max_hp}
        </p>
        <p data-test="unit-movement" class="text-sm">
          Movement {@unit.movement}/{@unit.max_movement}
        </p>
        <.order_summary order={@order} />

        <button
          :if={@unit.type == :settler}
          type="button"
          data-test="found-city"
          phx-click="found_city"
          phx-value-unit_id={@unit_id}
          class="btn btn-sm btn-primary"
        >
          Found City
        </button>

        <div :if={@unit.type == :worker} class="flex flex-col gap-1">
          <%!-- A dig in progress on the worker's tile is the loudest
               thing in the panel — silent success on Build reads as a
               dead button (issue b5cc4ae9). --%>
          <div
            :if={@current_dig}
            class="badge badge-info gap-1 whitespace-nowrap"
            data-test="dig-progress"
          >
            Digging {improvement_label(@current_dig.kind)} — {@current_dig.progress}/{BrokenOaths.Game.Improvement.duration(
              @current_dig.kind
            )} turns
          </div>
          <.build_button
            :for={kind <- @allowed_improvements}
            :if={is_nil(@current_dig)}
            kind={kind}
            unit_id={@unit_id}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :unit_id, :any, required: true

  defp build_button(assigns) do
    ~H"""
    <button
      type="button"
      data-test={"build-#{@kind}"}
      phx-click="start_improvement"
      phx-value-unit_id={@unit_id}
      phx-value-kind={@kind}
      class="btn btn-sm btn-outline"
    >
      Build {improvement_label(@kind)}
    </button>
    """
  end

  defp improvement_label(:farm), do: "Farm"
  defp improvement_label(:mine), do: "Mine"
  defp improvement_label(:road), do: "Road"
  defp improvement_label(:pasture), do: "Pasture"

  attr :order, :map, default: nil

  defp order_summary(%{order: nil} = assigns) do
    ~H"""
    <p data-test="unit-order" class="text-sm text-base-content/60">
      No orders queued
    </p>
    """
  end

  defp order_summary(%{order: %{status: :interrupted}} = assigns) do
    ~H"""
    <p data-test="unit-order" class="text-sm">
      Moving to tile {@order.target_tile}
      <span data-test="order-interrupted" class="badge badge-warning badge-sm ml-1">
        Interrupted
      </span>
    </p>
    """
  end

  defp order_summary(assigns) do
    ~H"""
    <p data-test="unit-order" class="text-sm">
      Moving to tile {@order.target_tile}
    </p>
    """
  end

  defp unit_type_label(:lord), do: "Lord"
  defp unit_type_label(:settler), do: "Settler"
  defp unit_type_label(:worker), do: "Worker"
  defp unit_type_label(:warrior), do: "Warrior"
  # Story 903's Bronze Age melee unit (issue b8f4ce10 — selecting one
  # crashed this component with a FunctionClauseError; a garrisoned
  # bronze_spearman also blocked left-clicking the city under it).
  defp unit_type_label(:bronze_spearman), do: "Bronze Spearman"
  # Enemy units are selectable too — the panel doubles as the threat
  # readout (stats, HP), with every action already type/owner-gated.
  defp unit_type_label(:barbarian_warrior), do: "Barbarian Warrior"
  # Any future unit type degrades to a readable label instead of
  # crashing the LiveView the way :bronze_spearman did before this fix.
  defp unit_type_label(type), do: type |> to_string() |> String.capitalize()
end
