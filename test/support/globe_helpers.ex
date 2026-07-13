defmodule BrokenOathsWeb.GlobeHelpers do
  @moduledoc """
  LiveView-test helpers for interacting with the globe board.

  Testability doctrine (see .code_my_spec/knowledge/): all game state is
  server-side and every game interaction is a LiveView event, so gameplay
  is fully testable without executing any client JS. Two entry points:

    * CLASSIC mode is the selector-testable board: tiles are
      server-rendered divs with `phx-value-id`, so `element/2` + camera
      URL params reach any tile. Use `camera_on/2` + `click_tile/2`.

    * GLOBE (canvas) mode has no tile DOM by design; drive it through the
      same server events the hook sends: `select_tile_at/3` (clicks) and
      `look_at/3` (camera). These exercise the identical handle_event
      paths production uses.
  """

  import Phoenix.LiveViewTest

  alias BrokenOaths.Worlds.Globe

  @doc """
  Camera query params that center the view on a tile — mount with these
  and (in classic mode) the tile is on screen and clickable by selector:

      {:ok, view, _} = live(conn, ~p"/worlds/\#{world.id}?\#{camera_on(world, 42)}")
      click_tile(view, 42)
  """
  def camera_on(world, tile_id, zoom \\ 2000) do
    tile = world |> mesh() |> Globe.tile(tile_id)
    {lat, lon} = Globe.latlon(tile.center)
    [yaw: Float.round(lon, 2), pitch: Float.round(lat, 2), zoom: zoom]
  end

  @doc "Classic mode: click a tile through its server-rendered DOM element."
  def click_tile(view, tile_id) do
    view
    |> element("[phx-value-id='#{tile_id}']")
    |> render_click()
  end

  @doc """
  Globe (canvas) mode: select a tile exactly as a production click does —
  the hook inverse-projects to a unit-sphere point and pushes select_at;
  here we push the tile's own center, which resolves to that tile.
  """
  def select_tile_at(view, world, tile_id) do
    {x, y, z} = (world |> mesh() |> Globe.tile(tile_id)).center

    view
    |> element("#globe3d-stage")
    |> render_hook("select_at", %{x: x, y: y, z: z})
  end

  @doc "Globe mode: move the settled camera (as a drag-end view_sync would)."
  def look_at(view, world, tile_id, zoom \\ 2000) do
    tile = world |> mesh() |> Globe.tile(tile_id)
    {lat, lon} = Globe.latlon(tile.center)

    view
    |> element("#globe3d-stage")
    |> render_hook("view_sync", %{
      yaw: lon * :math.pi() / 180,
      pitch: lat * :math.pi() / 180,
      scale: zoom,
      settled: true
    })
  end

  defp mesh(world), do: Globe.get(world.frequency)
end
