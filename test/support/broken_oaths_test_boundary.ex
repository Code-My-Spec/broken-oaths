defmodule BrokenOathsTest do
  use Boundary, top_level?: true, deps: [BrokenOaths], exports: [ConnCase, DataCase]
end
