defmodule BrokenOathsWeb.DevQaController do
  @moduledoc """
  Dev-only QA control surface — lets a QA agent construct and control a
  live multiplayer game scenario deterministically over plain curl calls
  (spawn/heal/reposition units, clear barbarians, set camp HP, and —
  most importantly — pause the turn clock and step turns on demand).

  Mounted ONLY inside `lib/broken_oaths_web/router.ex`'s
  `Application.compile_env(:broken_oaths, :dev_routes)` gate — the same
  block guarding LiveDashboard, `false` in prod (see `config/prod.exs`),
  so this module and its routes never exist in a production build. No
  auth: dev-only, localhost.

  Every action is a thin wrapper around `BrokenOaths.Game`'s existing
  (or newly added) `*_for_test` / `pause_ticks` / `resume_ticks` /
  `advance_turn` functions — see that module's docs for the underlying
  semantics. World state is loaded via `BrokenOaths.Worlds.get_world!/1`
  (raises `Ecto.NoResultsError`, rendered as a 404 by the default error
  views, for an unknown world id).

  ## Endpoints

  All paths are rooted at `/dev/qa/worlds/:id` (`:id` is the world id):

  | Method | Path                | Body / query params           | What it does |
  |---|---|---|---|
  | GET    | `/`                 | —                              | `%{id, turn, turn_seconds, paused}` |
  | POST   | `/pause`            | —                              | Freeze the turn clock |
  | POST   | `/resume`           | —                              | Unfreeze the turn clock |
  | POST   | `/step`             | —                              | Advance exactly one turn (works even while paused) |
  | POST   | `/units`            | `player_id, type, tile_id`     | Spawn a player-owned unit |
  | POST   | `/barbarians`       | `tile_id, camp_id` (optional)  | Spawn a barbarian warrior |
  | PATCH  | `/units/:unit_id`   | `hp?, tile_id?, recharge?`     | Set HP / relocate / recharge movement (any combination) |
  | DELETE | `/units/:unit_id`   | —                               | Hard-delete a unit |
  | PATCH  | `/camps/:camp_id`   | `hp`                            | Set a camp's HP directly |

  ## Example curl calls

      curl -X POST http://localhost:4050/dev/qa/worlds/1/pause
      curl http://localhost:4050/dev/qa/worlds/1
      curl -X POST http://localhost:4050/dev/qa/worlds/1/units \\
        -d player_id=3 -d type=warrior -d tile_id=120
      curl -X PATCH http://localhost:4050/dev/qa/worlds/1/units/42 -d hp=10
      curl -X PATCH http://localhost:4050/dev/qa/worlds/1/units/42 -d tile_id=121
      curl -X DELETE http://localhost:4050/dev/qa/worlds/1/units/42
      curl -X PATCH http://localhost:4050/dev/qa/worlds/1/camps/7 -d hp=1
      curl -X POST http://localhost:4050/dev/qa/worlds/1/step
      curl -X POST http://localhost:4050/dev/qa/worlds/1/resume
  """

  use BrokenOathsWeb, :controller

  alias BrokenOaths.Game
  alias BrokenOaths.Worlds

  @unit_types ~w(warrior worker settler lord)a

  def show(conn, %{"id" => id}) do
    world = Worlds.get_world!(id)

    json(conn, %{
      id: world.id,
      turn: Game.turn_number(world),
      turn_seconds: world.turn_seconds,
      paused: Game.paused?(world)
    })
  end

  def pause(conn, %{"id" => id}) do
    world = Worlds.get_world!(id)
    :ok = Game.pause_ticks(world)
    json(conn, %{ok: true, paused: true})
  end

  def resume(conn, %{"id" => id}) do
    world = Worlds.get_world!(id)
    :ok = Game.resume_ticks(world)
    json(conn, %{ok: true, paused: false})
  end

  def step(conn, %{"id" => id}) do
    world = Worlds.get_world!(id)
    :ok = Game.advance_turn(world)
    json(conn, %{ok: true, turn: Game.turn_number(world)})
  end

  def spawn_unit(conn, %{"id" => id} = params) do
    world = Worlds.get_world!(id)

    with {:ok, player_id} <- parse_int(params["player_id"], "player_id"),
         {:ok, type} <- parse_unit_type(params["type"]),
         {:ok, tile_id} <- parse_int(params["tile_id"], "tile_id") do
      unit = Game.spawn_unit_for_test(world, player_id, type, tile_id)
      conn |> put_status(:created) |> json(unit)
    else
      {:error, reason} -> bad_request(conn, reason)
    end
  end

  def spawn_barbarian(conn, %{"id" => id} = params) do
    world = Worlds.get_world!(id)

    with {:ok, tile_id} <- parse_int(params["tile_id"], "tile_id"),
         {:ok, camp_id} <- parse_optional_int(params["camp_id"], "camp_id") do
      unit = Game.spawn_barbarian_for_test(world, tile_id, camp_id)
      conn |> put_status(:created) |> json(unit)
    else
      {:error, reason} -> bad_request(conn, reason)
    end
  end

  def update_unit(conn, %{"id" => id, "unit_id" => unit_id_param} = params) do
    world = Worlds.get_world!(id)

    with {:ok, unit_id} <- parse_int(unit_id_param, "unit_id"),
         :ok <- maybe_set_hp(world, unit_id, params["hp"]),
         :ok <- maybe_relocate(world, unit_id, params["tile_id"]),
         :ok <- maybe_recharge(world, unit_id, params["recharge"]) do
      json(conn, %{ok: true})
    else
      {:error, reason} -> bad_request(conn, reason)
    end
  end

  def delete_unit(conn, %{"id" => id, "unit_id" => unit_id_param}) do
    world = Worlds.get_world!(id)

    case parse_int(unit_id_param, "unit_id") do
      {:ok, unit_id} ->
        :ok = Game.remove_unit_for_test(world, unit_id)
        json(conn, %{ok: true})

      {:error, reason} ->
        bad_request(conn, reason)
    end
  end

  def update_camp(conn, %{"id" => id, "camp_id" => camp_id_param} = params) do
    world = Worlds.get_world!(id)

    with {:ok, camp_id} <- parse_int(camp_id_param, "camp_id"),
         {:ok, hp} <- parse_int(params["hp"], "hp") do
      :ok = Game.set_camp_hp_for_test(world, camp_id, hp)
      json(conn, %{ok: true})
    else
      {:error, reason} -> bad_request(conn, reason)
    end
  end

  # -------------------------------------------------------------------
  # Param parsing / errors
  # -------------------------------------------------------------------

  defp maybe_set_hp(_world, _unit_id, nil), do: :ok

  defp maybe_set_hp(world, unit_id, hp) do
    with {:ok, hp} <- parse_int(hp, "hp") do
      Game.set_unit_hp_for_test(world, unit_id, hp)
    end
  end

  defp maybe_relocate(_world, _unit_id, nil), do: :ok

  defp maybe_relocate(world, unit_id, tile_id) do
    with {:ok, tile_id} <- parse_int(tile_id, "tile_id") do
      Game.relocate_unit_for_test(world, unit_id, tile_id)
    end
  end

  defp maybe_recharge(_world, _unit_id, recharge) when recharge in [nil, false, "false"], do: :ok
  defp maybe_recharge(world, unit_id, _truthy), do: Game.recharge_unit_for_test(world, unit_id)

  defp parse_unit_type(value) when value in ["warrior", "worker", "settler", "lord"],
    do: {:ok, String.to_existing_atom(value)}

  defp parse_unit_type(value) when value in @unit_types, do: {:ok, value}
  defp parse_unit_type(other), do: {:error, "invalid unit type: #{inspect(other)}"}

  defp parse_optional_int(nil, _field), do: {:ok, nil}
  defp parse_optional_int(value, field), do: parse_int(value, field)

  defp parse_int(value, _field) when is_integer(value), do: {:ok, value}

  defp parse_int(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "#{field} must be an integer, got: #{inspect(value)}"}
    end
  end

  defp parse_int(_value, field), do: {:error, "#{field} is required"}

  defp bad_request(conn, reason) do
    conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
  end
end
