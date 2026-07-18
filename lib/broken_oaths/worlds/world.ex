defmodule BrokenOaths.Worlds.World do
  @moduledoc """
  A generated hex world: seed, mesh frequency, turn tracking, and the
  world's own turn-boundary cadence (`turn_seconds`, story 897) — a
  QA-fast world ticks every 5s while the default pace stays the
  original 60s, each independently, since `turn_seconds` is read off
  this struct rather than a single hardcoded process-wide constant
  (see `BrokenOaths.Game.WorldServer`'s ticking doc).

  `turn_seconds` is set once, at creation, via `creation_changeset/2`
  (`Worlds.create_world/1`) and never cast by the ordinary
  `changeset/2` (`Worlds.update_world/2`) — a world's pace is a launch
  decision, not something that can drift out from under a game already
  in progress.

  `paused` is a dev-only QA control flag (see
  `BrokenOathsWeb.DevQaController` and `BrokenOaths.Game.WorldServer`'s
  ticking doc) — a paused world's turn clock never advances on its own,
  though `WorldServer.call(world, :advance_turn)` still steps it
  manually. Persisted so a paused QA world stays frozen across a
  server restart.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "worlds" do
    field :name, :string
    field :seed, :integer
    field :frequency, :integer, default: 54
    field :status, :string, default: "active"
    field :turn, :integer, default: 0
    field :turn_started_at, :utc_datetime
    field :turn_seconds, :integer, default: 60
    field :paused, :boolean, default: false

    timestamps()
  end

  def changeset(world, attrs) do
    world
    |> cast(attrs, [:name, :seed, :frequency, :status, :turn, :turn_started_at, :paused])
    |> validate_required([:name, :seed])
    |> validate_number(:frequency, greater_than: 0, less_than_or_equal_to: 80)
    |> validate_number(:turn, greater_than_or_equal_to: 0)
    |> unique_constraint(:seed)
  end

  @doc "Changeset for a brand-new world — the only place `turn_seconds` may ever be set."
  def creation_changeset(world, attrs) do
    world
    |> changeset(attrs)
    |> cast(attrs, [:turn_seconds])
    |> validate_number(:turn_seconds, greater_than: 0)
  end
end
