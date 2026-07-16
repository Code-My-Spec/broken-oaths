defmodule BrokenOathsWeb.PageControllerTest do
  use BrokenOathsTest.ConnCase

  test "GET / renders the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Broken Oaths"
    assert response =~ "Play free"
    assert response =~ ~s|href="/play"|
  end
end
