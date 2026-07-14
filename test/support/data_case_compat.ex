defmodule BrokenOaths.DataCase do
  @moduledoc """
  Compatibility shim: Phoenix generators emit `use BrokenOaths.DataCase`.
  The real case module is `BrokenOathsTest.DataCase` — forward to it.
  """
  defmacro __using__(opts) do
    quote do
      use BrokenOathsTest.DataCase, unquote(opts)
    end
  end
end
