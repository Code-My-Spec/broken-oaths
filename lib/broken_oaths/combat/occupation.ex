defmodule BrokenOaths.Combat.Occupation do
  @moduledoc """
  Pure rules for a city held by another player. Occupation never changes the
  city owner; it only prevents military production until the city is freed.
  """

  @military_items [:warrior, :bronze_spearman, :archer, :galley, :scout]

  @spec occupied?(map()) :: boolean()
  def occupied?(%{occupied_by_player_id: occupier}) when not is_nil(occupier), do: true
  def occupied?(_city), do: false

  @spec military_item?(atom()) :: boolean()
  def military_item?(item), do: item in @military_items

  @spec production_allowed?(map(), atom()) :: boolean()
  def production_allowed?(city, item), do: not occupied?(city) or not military_item?(item)

  @spec validate_production(map(), atom()) :: :ok | {:error, :occupied}
  def validate_production(city, item) do
    case production_allowed?(city, item) do
      true -> :ok
      false -> {:error, :occupied}
    end
  end

  @spec available_items(map(), [atom()]) :: [atom()]
  def available_items(city, items) do
    Enum.reject(items, &(occupied?(city) and military_item?(&1)))
  end
end
