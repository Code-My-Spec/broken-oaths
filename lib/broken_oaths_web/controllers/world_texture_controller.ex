defmodule BrokenOathsWeb.WorldTextureController do
  use BrokenOathsWeb, :controller

  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.Texture

  @doc """
  The baked equirectangular world texture for the far-zoom globe impostor.
  Clients bust the long-lived cache by appending ?seed= to the URL;
  ?level=0 serves the tiny first-paint variant.
  """
  def show(conn, %{"id" => id} = params) do
    world = Worlds.get_world!(id)
    level = if params["level"] == "0", do: 0, else: 1
    png = Texture.png(world.seed, world.frequency, level)
    send_png(conn, png)
  end

  @doc """
  The airspace (cloud layer) impostor texture — same equirect bake as
  the terrain, palette+tRNS PNG with per-tile cloud levels.
  """
  def airspace(conn, %{"id" => id} = params) do
    world = Worlds.get_world!(id)
    level = if params["level"] == "0", do: 0, else: 1
    png = Texture.airspace_png(world.seed, world.frequency, level)
    send_png(conn, png)
  end

  defp send_png(conn, png) do
    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> send_resp(200, png)
  end
end
