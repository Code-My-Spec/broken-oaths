defmodule BrokenOaths.Worlds do
  @moduledoc """
  Bounded context for hex world generation and management.
  Worlds are stored as metadata (seed, dimensions); terrain is generated on-demand.
  """
  import Ecto.Query
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.World

  @adjectives ~w(Ancient Emerald Crystal Shadow Golden Silver Crimson Azure Jade Iron
                 Mystic Frozen Verdant Obsidian Scarlet Sapphire Amber Onyx Ivory Coral)
  @nouns ~w(Shores Plains Peaks Realm Lands Kingdom Valley Coast Heights Wilds
            Expanse Wastes Depths Frontier Dominion Haven Reaches Steppes Tundra Isles)

  def list_worlds do
    Repo.all(from w in World, order_by: [desc: w.inserted_at, desc: w.id])
  end

  def get_world!(id), do: Repo.get!(World, id)

  def create_world(attrs \\ %{}) do
    %World{}
    |> World.creation_changeset(attrs)
    |> Repo.insert()
  end

  def update_world(%World{} = world, attrs) do
    world
    |> World.changeset(attrs)
    |> Repo.update()
  end

  def delete_world(%World{} = world) do
    Repo.delete(world)
  end

  def change_world(%World{} = world, attrs \\ %{}) do
    World.changeset(world, attrs)
  end

  @doc "Generate a random world name from a seed."
  def random_world_name(seed) do
    :rand.seed(:exsss, {seed, 0, 0})
    adj = Enum.random(@adjectives)
    noun = Enum.random(@nouns)
    "#{adj} #{noun}"
  end

  @doc """
  Create a fresh, empty, active full-size world ready for onboarding — a
  unique random seed, a generated name, the default frequency-54 globe (~110
  spawnable regions), and the standard 60s tick. Used to auto-scale when every
  existing world has filled up, so a new player always has somewhere to spawn.
  """
  def create_open_world do
    seed = unique_seed()
    create_world(%{name: random_world_name(seed), seed: seed, frequency: 54})
  end

  # A seed not already claimed by an existing world (worlds.seed is unique).
  # Any frequency-54 seed yields a habitable globe, so no spawn-region probing
  # is needed — only collision-avoidance against the unique index.
  defp unique_seed do
    candidate = :rand.uniform(2_000_000_000)

    if Repo.exists?(from w in World, where: w.seed == ^candidate),
      do: unique_seed(),
      else: candidate
  end
end
