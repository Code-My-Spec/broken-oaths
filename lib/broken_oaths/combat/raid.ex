defmodule BrokenOaths.Combat.Raid do
  @moduledoc """
  Pure wartime city-raiding rules. A raid transfers a fixed gold reward to
  the raider without altering the target city's health, owner, or occupation.
  """

  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Diplomacy.War
  alias BrokenOaths.Worlds.Regions

  @gold_reward 25

  @spec gold_reward() :: pos_integer()
  def gold_reward, do: @gold_reward

  @spec raid_city(map(), map(), term(), term()) ::
          {:ok, %{gold_gained: pos_integer()}, map()}
          | {:error,
             :not_owner
             | :invalid_target
             | :out_of_movement
             | :not_adjacent
             | :own_city
             | :not_military
             | :not_hostile}
  def raid_city(state, user, unit_id, city_id) do
    with %{id: player_id} = player <- player_for(state, user.id),
         %{player_id: ^player_id} = unit <- Map.get(state.units, unit_id),
         city when not is_nil(city) <- Map.get(state.cities, city_id),
         :ok <- validate_raid(state, unit, city) do
      new_state =
        state
        |> put_in([:units, unit.id], %{unit | movement: 0})
        |> update_in([:players, player.id, :gold], &(&1 + gold_reward()))

      {:ok, %{gold_gained: gold_reward()}, new_state}
    else
      nil -> {:error, :invalid_target}
      %{player_id: _other_player_id} -> {:error, :not_owner}
      false -> {:error, :not_owner}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_raid(state, unit, city) do
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, unit.tile_id)

    case CityDefense.military?(unit) do
      false -> {:error, :not_military}
      true -> validate_target(state, unit, city, adjacent_tile_ids)
    end
  end

  defp validate_target(_state, %{movement: movement}, _city, _adjacent_tile_ids)
       when movement <= 0,
       do: {:error, :out_of_movement}

  defp validate_target(_state, unit, %{player_id: player_id}, _adjacent_tile_ids)
       when unit.player_id == player_id,
       do: {:error, :own_city}

  defp validate_target(state, unit, city, adjacent_tile_ids) do
    case city.tile_id in adjacent_tile_ids do
      false -> {:error, :not_adjacent}
      true -> validate_wartime_target(state, unit, city)
    end
  end

  defp validate_wartime_target(state, unit, city) do
    case opponent_for(state, city.player_id) do
      nil ->
        {:error, :invalid_target}

      opponent ->
        case War.active?(state.world.id, unit.player_id, opponent.id) do
          true -> :ok
          false -> {:error, :not_hostile}
        end
    end
  end

  defp player_for(state, user_id) do
    state.players
    |> Map.values()
    |> Enum.find(&(&1.user_id == user_id))
  end

  defp opponent_for(state, player_id), do: Map.get(state.players, player_id)
end
