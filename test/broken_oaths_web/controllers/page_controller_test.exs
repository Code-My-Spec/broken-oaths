defmodule BrokenOathsWeb.PageControllerTest do
  use BrokenOathsTest.ConnCase

  test "GET / renders the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Broken Oaths"
    assert response =~ "Play free"
    assert response =~ ~s|href="/play"|
    # Lander describes the full arc and links out to the roadmap.
    assert response =~ "intergalactic"
    assert response =~ ~s|href="/roadmap"|
  end

  test "GET /roadmap renders the public roadmap", %{conn: conn} do
    conn = get(conn, ~p"/roadmap")
    response = html_response(conn, 200)
    assert response =~ "Roadmap"
    # The political ladder tiers, shipped through vision.
    assert response =~ "Vassalage"
    assert response =~ "Playable now"
    assert response =~ "Colonialism"
    assert response =~ "Hegemony"
    assert response =~ "god"
    assert response =~ ~s|href="/play"|
  end
end
