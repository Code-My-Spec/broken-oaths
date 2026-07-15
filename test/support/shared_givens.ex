defmodule BrokenOathsSpex.SharedGivens do
  @moduledoc """
  Shared `given_ :atom` steps for BDD specs. Import with a plain
  `import BrokenOathsSpex.SharedGivens` in a spex module.
  """

  use SexySpex.Givens

  alias BrokenOathsSpex.Fixtures

  # A confirmed player logged in on `context.conn` (`context.user`).
  register_given :registered_player, context do
    user = Fixtures.user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> BrokenOathsTest.ConnCase.log_in_user(user)

    {:ok, context |> Map.put(:user, user) |> Map.put(:conn, conn)}
  end

  # A second player with their own session (`context.other_user` /
  # `context.other_conn`) — for multiplayer scenarios.
  register_given :second_registered_player, context do
    user = Fixtures.user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> BrokenOathsTest.ConnCase.log_in_user(user)

    {:ok, context |> Map.put(:other_user, user) |> Map.put(:other_conn, conn)}
  end

  # A third player with their own session (`context.third_user` /
  # `context.third_conn`) — for scenarios needing several civilizations
  # at once (e.g. surrounding a single city with blockers).
  register_given :third_registered_player, context do
    user = Fixtures.user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> BrokenOathsTest.ConnCase.log_in_user(user)

    {:ok, context |> Map.put(:third_user, user) |> Map.put(:third_conn, conn)}
  end

  # A deterministic world (`context.world`) — fixture frequency, seed 424242.
  register_given :a_world, context do
    {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 424_242}))}
  end
end
