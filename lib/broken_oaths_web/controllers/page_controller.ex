defmodule BrokenOathsWeb.PageController do
  use BrokenOathsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
