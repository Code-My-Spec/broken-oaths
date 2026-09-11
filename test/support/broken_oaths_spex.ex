defmodule BrokenOathsSpex do
  @moduledoc false
  use Boundary,
    top_level?: true,
    deps: [BrokenOathsTest, BrokenOathsWeb, BrokenOathsSpex.Fixtures]
end
