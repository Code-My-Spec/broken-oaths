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

  test "serves the half-size first-paint texture at level 0", %{conn: conn} do
    world = world_fixture(%{seed: 4243})

    conn = get(conn, ~p"/worlds/#{world.id}/texture.png?level=0")

    body = response(conn, 200)
    # Test config is 128x64, so level 0 is 64x32 (from the IHDR chunk)
    assert <<_::binary-size(16), 64::32, 32::32, _::binary>> = body
  end

  test "serves the cloud-cover map", %{conn: conn} do
    world = world_fixture(%{seed: 4244})

    conn = get(conn, ~p"/worlds/#{world.id}/clouds.png")
    assert <<137, 80, 78, 71, _::binary>> = response(conn, 200)
    assert response_content_type(conn, :png) =~ "image/png"
  end

  test "404s for a missing world", %{conn: conn} do
    assert_error_sent 404, fn ->
      get(conn, ~p"/worlds/0/texture.png")
    end
  end
end
