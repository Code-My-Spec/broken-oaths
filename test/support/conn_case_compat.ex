defmodule BrokenOathsWeb.ConnCase do
  @moduledoc """
  Compatibility shim: Phoenix generators emit `use BrokenOathsWeb.ConnCase`.
  The real case module is `BrokenOathsTest.ConnCase` — forward to it.
  """
  defmacro __using__(opts) do
    quote do
      use BrokenOathsTest.ConnCase, unquote(opts)
    end
  end
end
