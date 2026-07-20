defmodule BrokenOaths.Game.Turn.HeirSuccession do
  @moduledoc """
  Story 896's heir-succession phase: any player whose lord died
  (scheduled by `BrokenOaths.Game.WorldServer`'s combat handler, or by
  `BrokenOaths.Game.Turn.BarbarianPhase`'s own barbarian-initiated kill,
  into `state.pending_heirs`, `%{player_id => arrival_turn}` — not part
  of `BrokenOaths.Game.Turn`'s own canonical state contract, read
  defensively via `Map.get(state, :pending_heirs, %{})` since most
  hand-built tick-state test maps predate this field) whose
  `arrival_turn` has now passed gets a fresh Lord at their capital
  (their oldest city, by id) this tick, plus a `{:lineage_continued,
  user_id, message}` event so only that player is notified (criterion
  7573). A player with no surviving city simply never gets their heir
  back — an edge case no story covers.

  `pending_heirs` is a scheduled arrival turn, not a fact about any
  single domain model (`BrokenOaths.Game.Player` is a thin schema, and
  a fallen lord's replacement touches `Player`/`Unit`/`City` at once),
  so this phase lives on the turn pipeline itself rather than on any
  one of its siblings — `state` throughout is the canonical tick-state
  described in `BrokenOaths.Game.Turn`.
  """

  @doc "Spawn a fresh Lord for every player whose `pending_heirs` arrival turn has passed."
  @spec resolve(map(), non_neg_integer()) :: {map(), [tuple()]}
  def resolve(state, new_turn) do
    state = Map.put_new(state, :pending_heirs, %{})

    due =
      for {player_id, arrival_turn} <- state.pending_heirs, new_turn >= arrival_turn do
        player_id
      end

    Enum.reduce(due, {state, []}, &resolve_heir/2)
  end

  defp resolve_heir(player_id, {state, events}) do
    state = %{state | pending_heirs: Map.delete(state.pending_heirs, player_id)}

    case capital_city(state.cities, player_id) do
      nil ->
        {state, events}

      city ->
        spawn_event = %{player_id: player_id, type: :lord, tile_id: city.tile_id}
        user_id = Map.fetch!(state.players, player_id).user_id
        message = "Your lord has fallen, but the line endures — a new lord takes the throne."

        {state, events ++ [{:unit_spawned, spawn_event}, {:lineage_continued, user_id, message}]}
    end
  end

  defp capital_city(cities, player_id) do
    cities
    |> Map.values()
    |> Enum.filter(&(&1.player_id == player_id))
    |> Enum.min_by(& &1.id, fn -> nil end)
  end
end
