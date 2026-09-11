defmodule BrokenOathsTest do
  @moduledoc false
  use Boundary, top_level?: true, deps: [BrokenOaths], exports: [ConnCase, DataCase]
end
