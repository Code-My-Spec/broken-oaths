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
        width: 200,
        height: 150
      })
      |> Worlds.create_world()

    world
  end

  def small_world_fixture(attrs \\ %{}) do
    world_fixture(Map.merge(%{width: 20, height: 15}, attrs))
  end
end
