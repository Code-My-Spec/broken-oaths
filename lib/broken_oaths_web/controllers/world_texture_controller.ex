defmodule BrokenOathsWeb.WorldTextureController do
  use BrokenOathsWeb, :controller

  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.Texture

  @doc """
  The baked equirectangular world texture for the far-zoom globe impostor.
  Clients bust the long-lived cache by appending ?seed= to the URL.
  """
  def show(conn, %{"id" => id}) do
    world = Worlds.get_world!(id)
    png = Texture.png(world.seed, world.frequency)

    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> send_resp(200, png)
  end
end
