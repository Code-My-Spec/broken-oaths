defmodule BrokenOathsWeb.GameLive.JoinTest do
  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BrokenOaths.UsersFixtures

  alias BrokenOaths.Users

  describe "display name (playtest issue 2a9df843)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders the display-name form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/play")

      assert html =~ ~s(data-test="display-name-input")
      assert html =~ "Your display name"
    end

    test "a player can choose the name other players will see", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/play")

      result =
        lv
        |> form("#display-name-form", %{"user" => %{"display_name" => "Rowan"}})
        |> render_submit()

      # The saved handle is reflected back in the form's value.
      assert result =~ ~s(value="Rowan")
      assert Users.get_user!(user.id).display_name == "Rowan"
    end

    test "a blank name clears back to the fallback", %{conn: conn, user: user} do
      {:ok, _} = Users.update_user_display_name(user, %{display_name: "Rowan"})

      {:ok, lv, _html} = live(conn, ~p"/play")

      lv
      |> form("#display-name-form", %{"user" => %{"display_name" => "   "}})
      |> render_submit()

      assert Users.get_user!(user.id).display_name == nil
    end

    test "a too-short name is rejected", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/play")

      result =
        lv
        |> form("#display-name-form", %{"user" => %{"display_name" => "ab"}})
        |> render_submit()

      assert result =~ "should be at least 3 character"
      assert Users.get_user!(user.id).display_name == nil
    end
  end
end
