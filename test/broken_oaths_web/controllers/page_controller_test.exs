defmodule BrokenOathsWeb.PageControllerTest do
  use BrokenOathsTest.ConnCase

  test "GET / redirects into the game", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/play"
  end
end
