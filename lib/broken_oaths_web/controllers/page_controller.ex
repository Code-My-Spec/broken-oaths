defmodule BrokenOathsWeb.PageController do
  use BrokenOathsWeb, :controller

  # The game IS the home page: `/` sends visitors straight into the
  # world picker. Unauthenticated visitors bounce through login/register
  # on the way (require_authenticated_user on /play).
  def home(conn, _params) do
    redirect(conn, to: ~p"/play")
  end
end
