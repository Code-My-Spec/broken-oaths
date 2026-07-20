defmodule BrokenOaths.Players.Presence do
  @moduledoc """
  Per-player online/offline status within a world — which players
  currently hold a live LiveView connection to `BrokenOaths.Game.
  WorldServer`'s own board (`BrokenOathsWeb.GameLive.Play`).

  Fills a real gap: the world-process architecture already tracks
  coarse, WORLD-level liveness (a `BrokenOaths.Game.WorldServer`'s own
  ticking; nothing about a single player's own connection), but nothing
  before this module could answer "is THIS player online right now" —
  the question both Gold Bank accrual (story 909, offline-vs-logged-in
  gold routing) and Feudal Stewardship eligibility (story 910, a
  steward may only act while the owner is away) need to ask.

  ## Design

  Server-owned via a dedicated `Registry` (`BrokenOaths.
  PresenceRegistry`, `keys: :duplicate`, started under
  `BrokenOathsWeb.Application`) rather than a field inside
  `WorldServer`'s own canonical tick-state: presence is deliberately
  EPHEMERAL (never persisted, and correctly forgotten on every
  process/node restart — an offline player should never be stuck
  "online" forever because a server crashed mid-session), whereas
  `WorldServer`'s state is the durable, rehydrate-from-the-DB kind
  every other piece of tick-state already is. A `Registry` also gives
  connect/disconnect tracking for free: `connect/2` registers the
  calling process under a `{world_id, user_id}` key, and the Registry's
  own process monitor removes that entry automatically the instant the
  registering process exits — normally (a page navigation) or by
  crashing — with no explicit teardown call required. `disconnect/2` is
  offered anyway for a caller that wants to drop its OWN registration
  early without waiting to exit.

  A player connected in several tabs (or reconnecting before the old
  LiveView has fully exited) registers once per connection under the
  SAME key — `:duplicate` keys allow that, and `online?/2` only cares
  whether at least one registration exists, not how many.
  """

  @registry BrokenOaths.PresenceRegistry

  @type world :: %{id: term()}
  @type user :: %{id: term()}

  @doc """
  Registers the calling process as `user`'s own live connection to
  `world` — call this from `BrokenOathsWeb.GameLive.Play`'s `mount/3`
  once `connected?/1` is true. Idempotent: registering the same process
  under the same key twice is a harmless no-op (`Registry.register/3`'s
  own `{:error, {:already_registered, _}}` is swallowed).
  """
  @spec connect(world(), user()) :: :ok
  def connect(world, user) do
    case Registry.register(@registry, key(world, user), nil) do
      {:ok, _owner} -> :ok
      {:error, {:already_registered, _pid}} -> :ok
    end
  end

  @doc """
  Explicitly drops the calling process's own registration for `user` in
  `world` — never required (a dead process is removed automatically),
  but available for a caller that wants to signal "offline" before it
  actually exits.
  """
  @spec disconnect(world(), user()) :: :ok
  def disconnect(world, user), do: Registry.unregister(@registry, key(world, user))

  @doc "Whether `user` currently holds at least one live connection to `world`."
  @spec online?(world(), user()) :: boolean()
  def online?(world, user), do: Registry.lookup(@registry, key(world, user)) != []

  @doc "Every user id currently connected to `world` — the roster a steward-eligibility scan reads."
  @spec online_user_ids(world()) :: [term()]
  def online_user_ids(world) do
    @registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.filter(fn {world_id, _user_id} -> world_id == world.id end)
    |> Enum.map(fn {_world_id, user_id} -> user_id end)
    |> Enum.uniq()
  end

  defp key(world, user), do: {world.id, user.id}
end
