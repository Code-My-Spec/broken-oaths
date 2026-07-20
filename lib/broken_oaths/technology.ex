defmodule BrokenOaths.Technology do
  @moduledoc """
  A player's Ancient-era tech tree progress within a world (story 902).
  Thin `GenServer.call` wrappers onto each world's `BrokenOaths.Game.
  WorldServer`; see `BrokenOaths.Game`'s own moduledoc for the process
  architecture every world-scoped function here round-trips through.
  `tech_catalog/0` is the one exception — it is world-independent, a
  direct pass-through onto `BrokenOaths.Technology.Research.catalog/0`.

  Extracted from `BrokenOaths.Game` (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target) — every function below is
  `defdelegate`d back onto `BrokenOaths.Game` unchanged, so no caller
  needs to know this module exists.
  """

  alias BrokenOaths.Simulation.WorldServer
  alias BrokenOaths.Technology.Research

  @doc """
  The Stone Age tech catalog: `%{tech => %{cost:, unlock:}}` — every
  tech's science cost and unlock description, unrelated to any single
  world (`BrokenOaths.Technology.Research.catalog/0`). What a future
  TechPanel lists.
  """
  @spec tech_catalog() :: map()
  def tech_catalog, do: Research.catalog()

  @doc """
  `user`'s research state in `world` (story 902, expanded to the
  eleven-tech Ancient-era tree per issue 133b4893): `%{completed_techs:,
  current_research:, banked_science:, progress:, science_per_turn:}`,
  or `nil` if `user` hasn't joined `world` — `progress` is
  `%{tech:, banked:, cost:}` for `current_research`, or `nil` with
  nothing selected (see `BrokenOaths.Technology.Research.progress/1`).
  `science_per_turn` is `2 * population` summed over every one of
  `user`'s cities, right now (`BrokenOaths.Technology.Research.science_per_turn/1`).
  `banked_science` and `completed_techs` are both keyed/valued by tech
  atom (`BrokenOaths.Technology.Research.techs/0` names the full eleven-tech
  set).
  """
  @spec player_research(map(), map()) :: map() | nil
  def player_research(world, user), do: WorldServer.call(world, {:player_research, user})

  @doc """
  Select `tech` as `user`'s `current_research` in `world`, retaining
  whatever science was already banked toward it
  (`BrokenOaths.Technology.Research.set_research/2`). Refuses an unknown tech,
  one already completed, or — since the tree grew prerequisite edges —
  one whose prerequisites aren't all completed yet
  (`{:error, :prereqs_not_met}`, see `BrokenOaths.Technology.Research.prereqs_met?/2`).
  Persists immediately, like `rename_city/4` — no turn boundary required.
  """
  @spec set_research(map(), map(), atom()) ::
          :ok
          | {:error, :not_a_player | :invalid_tech | :already_completed | :prereqs_not_met}
  def set_research(world, user, tech), do: WorldServer.call(world, {:set_research, user, tech})
end
