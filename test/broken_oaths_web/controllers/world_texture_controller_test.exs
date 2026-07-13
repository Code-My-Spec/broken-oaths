defmodule BrokenOathsWeb.WorldTextureControllerTest do
  use BrokenOathsWeb.ConnCase, async: true

  import BrokenOaths.WorldsFixtures

  test "serves the baked world texture as an immutable PNG", %{conn: conn} do
    world = world_fixture(%{seed: 4242})

    conn = get(conn, ~p"/worlds/#{world.id}/texture.png")

    assert response_content_type(conn, :png) =~ "image/png"
    assert [cache] = get_resp_header(conn, "cache-control")
    assert cache =~ "immutable"
    assert <<137, 80, 78, 71, _::binary>> = response(conn, 200)
  end

  test "404s for a missing world", %{conn: conn} do
    assert_error_sent 404, fn ->
      get(conn, ~p"/worlds/0/texture.png")
    end
  end
end
