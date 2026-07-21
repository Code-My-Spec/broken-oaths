defmodule BrokenOaths.Vision do
  @moduledoc """
  Fog-filtered read surface — "what does the fog show" for a player
  right now. Thin `GenServer.call` wrappers onto each world's
  `BrokenOaths.Simulation.WorldServer`; see `BrokenOaths.Game`'s own moduledoc
  for the process architecture every function here round-trips through.

  Extracted from `BrokenOaths.Game` (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target) — every function below is
  `defdelegate`d back onto `BrokenOaths.Game` unchanged, so no caller
  needs to know this module exists.
  """

  alias BrokenOaths.Simulation.WorldServer

  @doc "Fog-filtered units `user` can currently see — own units always, others only while visible."
  def units_visible_to(world, user), do: WorldServer.call(world, {:units_visible_to, user})

  @doc "`%{visible: [tile_id], explored: [tile_id]}` for `user`."
  def visibility(world, user), do: WorldServer.call(world, {:visibility, user})

  @doc """
  Barbarian camps `user` currently knows about — inside their own
  claimed region (immediate, no scouting required) or already
  explored. The fog-filtered surface `GameLive.Play` pushes as
  "game:camps" (story 892, criterion 7546 — a HARD constraint: a camp
  outside both sets never appears here).
  """
  def camps_visible_to(world, user), do: WorldServer.call(world, {:camps_visible_to, user})

  @doc """
  Enemy (another player's own) cities `user` currently knows about
  (QA issue 56ee521a): `[%{id:, name:, tile_id:, size:}]`, fog-filtered
  the same "own region OR explored" way `camps_visible_to/2` already
  is, minus any city `user` has personally captured (see
  `captured_cities_visible_to/2` for those). Empty unless
  `feudal_enabled?/0` — the surface `GameLive.Play` merges into its own
  `"game:cities"` push as `hostile: true` markers, powering both the
  right-click attack target and the adjacent-unit attack affordance.
  """
  @spec enemy_cities_visible_to(map(), map()) :: [map()]
  def enemy_cities_visible_to(world, user),
    do: WorldServer.call(world, {:enemy_cities_visible_to, user})

  @doc """
  Cities `user` has personally captured (QA issue ffa66192):
  `[%{id:, name:, tile_id:, fallen_garrison?:}]` — `fallen_garrison?`
  is whether a living defender of the ORIGINAL owner still awaits
  `resolve_garrison_fate/4`'s execute/release choice. Empty unless
  `feudal_enabled?/0`. Powers `GameLive.Play`'s own "Captured Cities"
  panel.
  """
  @spec captured_cities_visible_to(map(), map()) :: [map()]
  def captured_cities_visible_to(world, user),
    do: WorldServer.call(world, {:captured_cities_visible_to, user})

  @doc """
  Improvements on tiles the player knows (home region or explored) —
  same fog rule as `camps_visible_to/2`.
  """
  def improvements_visible_to(world, user),
    do: WorldServer.call(world, {:improvements_visible_to, user})

  @doc """
  The tile `target_user_id`'s nearest city or unit currently visible to
  `user` sits on — `nil` if nothing of theirs is in sight right now.
  Playtest issue 4's "click a known player to center the globe on
  them." See `Visibility.visible_tile_of/3`.
  """
  @spec visible_tile_of(map(), map(), term()) :: non_neg_integer() | nil
  def visible_tile_of(world, user, target_user_id),
    do: WorldServer.call(world, {:visible_tile_of, user, target_user_id})
end
