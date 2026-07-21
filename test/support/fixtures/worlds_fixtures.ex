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
        # Story 924 ships recharge_turns default 2, but existing tests assume
        # movement recharges EVERY turn — keep fixtures at 1 (behavior-
        # preserving); the tick-split tests pass recharge_turns: 2 explicitly.
        recharge_turns: 1
      })
      |> Worlds.create_world()

    world
  end
end
