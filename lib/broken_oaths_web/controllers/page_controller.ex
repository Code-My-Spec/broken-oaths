defmodule BrokenOathsWeb.PageController do
  use BrokenOathsWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "A living hex globe 4X")
  end
end
