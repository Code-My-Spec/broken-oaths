defmodule BrokenOathsWeb.GameLive.UnitPanel do
  @moduledoc """
  Selected unit details (type, HP, movement remaining) and its queued order.

  A presentational component mounted by `BrokenOathsWeb.GameLive.Play`,
  which owns unit selection and order state. This component never reads
  from `BrokenOaths.Game` itself — it only renders the assigns it's given:

    * `:id` - the DOM id for this component instance
    * `:unit` - the selected unit, or `nil` when nothing is selected.
      Expected to carry `:type` (`:lord` | `:settler`), `:hp`, `:max_hp`,
      `:movement`, `:max_movement`
    * `:order` - the unit's queued order, or `nil`. Expected to carry
      `:target_tile` and `:status` (`:pending` | `:interrupted`)
  """

  use BrokenOathsWeb, :live_component

  def render(%{unit: nil} = assigns) do
    ~H"""
    <div id={@id}></div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@id} data-test="unit-panel" class="card bg-base-200 shadow-sm">
      <div class="card-body gap-2">
        <h3 data-test="unit-type" class="card-title text-base">
          {unit_type_label(@unit.type)}
        </h3>
        <p data-test="unit-hp" class="text-sm">
          HP {@unit.hp}/{@unit.max_hp}
        </p>
        <p data-test="unit-movement" class="text-sm">
          Movement {@unit.movement}/{@unit.max_movement}
        </p>
        <.order_summary order={@order} />
      </div>
    </div>
    """
  end

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
end
