defmodule BrokenOaths.WorldsFixtures do
  @moduledoc "Test fixtures for the Worlds context."
  alias BrokenOaths.Worlds

  def unique_world_seed, do: :rand.uniform(999_999_999)

  def world_fixture(attrs \\ %{}) do
    {:ok, world} =
      attrs
      |> Enum.into(%{
        name: "Test World #{System.unique_integer([:positive])}",
        seed: unique_world_seed(),
        # Small globe (642 tiles) keeps LiveView tests fast
        frequency: 8,
        # recharge_turns is retired (timer inversion — movement always
        # recharges every tick now) but kept at 1 for backward compat with
        # anything still reading it.
        recharge_turns: 1,
        # Timer inversion ships economy_turns default 10, but existing tests
        # assume the economy (production/research/growth/income) advances
        # EVERY tick — keep fixtures at 1 (behavior-preserving); the
        # fast/economy split tests pass economy_turns explicitly.
        economy_turns: 1
      })
      |> Worlds.create_world()

    world
  end
end
