defmodule BrokenOaths.Cities.City do
  @moduledoc """
  A founded city — world/player/tile, a renameable name, accumulated
  food and size, claimed territory, and which territory tiles are
  currently worked. Persisted like units/orders: the `WorldServer`
  holds the canonical in-memory copy (see `BrokenOaths.Simulation.Turn`'s
  moduledoc for the tick-state contract) and diffs it against this
  table on each command/tick.

  `territory` is every tile this city has ever claimed — permanent,
  monotonically growing (founding ring, then one tile per growth; see
  `BrokenOaths.Cities.Yields`). `worked_tiles` is the subset of
  `territory`, excluding the always-free `tile_id` center, that
  currently has a citizen assigned; it can be shorter than `size` when
  a citizen has been manually unassigned or lost its post (a settler's
  population cost un-works a tile without un-claiming it — story 883).

  The production queue lives in a separate table
  (`BrokenOaths.Cities.ProductionItem`) rather than an embedded list:
  each item needs a stable, independently-addressable id for
  `cancel_production_item/4`, and insertion order (lowest id = head =
  current) is a natural fit for a `has_many`.

  ## Founding, worked tiles, rename (pragdave decomposition, slice 3)

  `found_city/3`, `assign_worked_tile/5`, and `rename_city/4` are the
  pure, process-unaware "domain model" home for the command logic
  `BrokenOaths.Simulation.WorldServer` used to bury inline as private
  `do_*` functions (see
  `.code_my_spec/knowledge/genserver_decomposition.md`). Each takes
  the WorldServer's own tick-`state` plus plain args and returns
  `{:ok, new_state} | {:error, reason}` — no `GenServer`, no
  `handle_*`, no process awareness; `WorldServer`'s own `handle_call`
  clauses are thin one-line delegations into this module. `player_cities/2`
  is the matching read: the per-player city list (`Game.player_cities/2`'s
  own backing read) formatted for `GameLive.CityPanel`.

  Coordinates its siblings directly, per the north star's "cross-cutting
  operations are orchestrated by their OWNING domain model calling its
  siblings" rule: `Production` for founding validation/territory and the
  per-turn production readout, `Yields` for the founding pop's worked-tile
  pick, `Camp`/`Camps` for the first-founding wilderness seed, and
  `CityDefense`/`Siege` for the read-only defense/status badges
  `player_cities/2` exposes.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias BrokenOaths.Combat.Camp
  alias BrokenOaths.Combat.Camps
  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Cities.Production
  alias BrokenOaths.Cities.ProductionItem
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Combat.Siege
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.Cities.Yields
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @max_hp 100

  # Story 930 — the four new buildings (see `BrokenOaths.Cities.Buildings`'s
  # own moduledoc for why they land in a LIST rather than four more
  # `has_*` booleans). `has_granary` itself is untouched. Story 933
  # adds the Pyramids and Hanging Gardens WORLD WONDERS to the same
  # list — see `Buildings`'s own moduledoc, "Wonders", for why a
  # wonder is still just another `buildings` entry at the storage
  # layer even though its own cap (one per WORLD, not one per city)
  # is enforced a level up, in `Production.can_queue?/3`.
  @buildings [:library, :ancient_walls, :barracks, :water_mill, :pyramids, :hanging_gardens]

  @type building ::
          :library | :ancient_walls | :barracks | :water_mill | :pyramids | :hanging_gardens

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          tile_id: integer() | nil,
          size: pos_integer(),
          food: non_neg_integer(),
          territory: [integer()],
          worked_tiles: [integer()],
          hp: non_neg_integer(),
          production_halted_until: integer() | nil,
          has_granary: boolean(),
          buildings: [building()],
          occupied_by_player_id: integer() | nil,
          world_id: integer() | nil,
          player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player: Player.t() | Ecto.Association.NotLoaded.t(),
          occupied_by_player: Player.t() | Ecto.Association.NotLoaded.t() | nil,
          production_items: [ProductionItem.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_cities" do
    field :name, :string
    field :tile_id, :integer
    field :size, :integer, default: 1
    field :food, :integer, default: 0
    field :territory, {:array, :integer}, default: []
    field :worked_tiles, {:array, :integer}, default: []
    # Story 895 — see `BrokenOaths.Combat.CityDefense` for the combat math
    # both fields back: `hp` (capped at 100, mirrors `game_camps.hp`)
    # and `production_halted_until` (nil until the city is ever
    # pillaged; the turn number its frozen production resumes at).
    field :hp, :integer, default: @max_hp
    field :production_halted_until, :integer
    # Story 902, criterion 7629 — flips once the Pottery-gated Granary
    # buildable completes (`BrokenOaths.Cities.Production`'s `:granary`
    # catalog entry); read back by `BrokenOaths.Cities.Yields.accrue_food/3`
    # for its +2 food/turn bonus.
    field :has_granary, :boolean, default: false
    # Story 930 — every OTHER building a city has completed (Library,
    # Ancient Walls, Barracks, Water Mill): see `BrokenOaths.Cities.
    # Buildings`'s own moduledoc for why these four land in a list
    # rather than four more `has_*` booleans alongside `has_granary`
    # above. Story 933 adds the Pyramids and Hanging Gardens wonders
    # to this same list — a wonder still records on the ONE city that
    # built it, exactly like a standard building; only its CAP (one
    # per world) and its EFFECT (empire-wide) work differently.
    field :buildings, {:array, Ecto.Enum}, values: @buildings, default: []
    # Story 906 — the siege capture flow (`BrokenOaths.Combat.Siege`):
    # `nil` while free (the owner's own, unoccupied by anyone else);
    # set to the captor's player once a broken (0 HP) city is walked
    # into. Peacetime rule (Round-5 decisions): the original owner
    # keeps running the city (production, worked tiles) — only the
    # tribute/levy relationship (story 908) and the last-free-city
    # check (story 907) key off this field.
    belongs_to :occupied_by_player, Player

    belongs_to :world, World
    belongs_to :player, Player
    has_many :production_items, ProductionItem

    timestamps()
  end

  @doc false
  def changeset(city, attrs) do
    city
    |> cast(attrs, [
      :world_id,
      :player_id,
      :tile_id,
      :name,
      :size,
      :food,
      :territory,
      :worked_tiles,
      :hp,
      :production_halted_until,
      :has_granary,
      :buildings,
      :occupied_by_player_id
    ])
    |> validate_required([:world_id, :player_id, :tile_id, :name, :size, :food])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_number(:size, greater_than_or_equal_to: 1, less_than_or_equal_to: 6)
    |> validate_number(:food, greater_than_or_equal_to: 0)
    |> validate_number(:hp,
      greater_than_or_equal_to: 0,
      # Story 930 — Ancient Walls raise a city's max HP above the base
      # 100 (`CityDefense.wall_hp_bonus/0`); the bound has to widen to
      # match, or a walled city's own regen (which persists via raw
      # `Repo.update_all`, never this changeset) would be the only path
      # that could ever legally push `hp` past this ceiling.
      less_than_or_equal_to: @max_hp + CityDefense.wall_hp_bonus()
    )
    |> validate_worked_tiles_within_size()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player)
    |> assoc_constraint(:occupied_by_player)
    |> unique_constraint([:world_id, :tile_id], name: :game_cities_world_id_tile_id_index)
  end

  # A citizen can be manually unassigned (worked_tiles shorter than
  # size) but never doubled up beyond one worked tile per pop.
  defp validate_worked_tiles_within_size(changeset) do
    size = get_field(changeset, :size)
    worked = get_field(changeset, :worked_tiles) || []

    if is_integer(size) and length(worked) > size do
      add_error(changeset, :worked_tiles, "cannot exceed size")
    else
      changeset
    end
  end

  # -------------------------------------------------------------------
  # Founding (moved from WorldServer's `do_found_city/3`, story 878)
  # -------------------------------------------------------------------

  @doc """
  Found a city on the settler's own tile: consumes the settler and
  drops a working city in its place, both in the same transaction
  (story 878, criterion 7463). The founding pop's worked-tile pick uses
  the exact same deterministic scoring growth uses later
  (`Yields.pick_worked_tile/2`), and a player's FIRST city (never a
  second, third, ...) seeds the wilderness around it
  (`spawn_wilderness_camps/3`, story 892).
  """
  @spec found_city(map(), map(), integer()) :: {:ok, map()} | {:error, atom()}
  def found_city(state, user, unit_id) do
    player = find_player(state, user.id)
    unit = Map.get(state.units, unit_id)

    cond do
      is_nil(player) or is_nil(unit) or unit.player_id != player.id ->
        {:error, :not_owner}

      unit.type != :settler ->
        {:error, :not_settler}

      true ->
        case Production.validate_founding(state.world, Map.values(state.cities), unit.tile_id) do
          {:error, reason} ->
            {:error, reason}

          :ok ->
            first_founding? =
              not Enum.any?(state.cities, fn {_id, c} -> c.player_id == player.id end)

            {:ok, city} = persist_found_city!(state, player, unit)

            new_state = %{
              state
              | cities: Map.put(state.cities, city.id, city),
                units: Map.delete(state.units, unit_id),
                orders: Map.delete(state.orders, unit_id)
            }

            new_state =
              if first_founding?,
                do: spawn_wilderness_camps(new_state, player, unit.tile_id),
                else: new_state

            {:ok, new_state}
        end
    end
  end

  # Story 892: a player's FIRST city (never a second, third, ...) seeds
  # the wilderness around it — see `Camps.place_wilderness/6`'s doc for
  # the near/far split. Placement is pure and deterministic; this is
  # just the imperative shell turning its tile picks into real,
  # immediately persisted `Camp` rows (same "persist right away, tick
  # only diffs later" pattern `persist_found_city!/3` already uses for
  # the city itself).
  defp spawn_wilderness_camps(state, player, city_tile_id) do
    home_region = player_region_tiles(state.world, player.region_id)
    explored = Map.get(state.explored, player.id, MapSet.new())
    # Units, existing camps (any player's founding may already have
    # placed some — game_camps carries a world+tile unique index), and
    # cities all block placement.
    occupied =
      [
        state.units |> Map.values() |> Enum.map(& &1.tile_id),
        state |> Map.get(:camps, %{}) |> Map.values() |> Enum.map(& &1.tile_id),
        state |> Map.get(:cities, %{}) |> Map.values() |> Enum.map(& &1.tile_id)
      ]
      |> List.flatten()
      |> MapSet.new()

    seed = {state.world.seed, city_tile_id}

    tiles =
      Camps.place_wilderness(state.world, city_tile_id, home_region, explored, occupied, seed)

    camps = Enum.map(tiles, &persist_camp!(state.world.id, &1))

    %{state | camps: Enum.reduce(camps, Map.get(state, :camps, %{}), &Map.put(&2, &1.id, &1))}
  end

  defp persist_camp!(world_id, tile_id) do
    {:ok, camp} =
      %Camp{}
      |> Camp.changeset(%{
        world_id: world_id,
        tile_id: tile_id,
        hp: Camp.max_hp(),
        spawn_counter: 0
      })
      |> Repo.insert()

    camp_map(camp)
  end

  # The settler is consumed and a working city stands in its place
  # immediately (story 878, criterion 7463) — both writes happen in one
  # transaction. The founding pop's worked-tile pick uses the exact
  # same deterministic scoring growth uses later, computed in memory
  # before insert since a size-1 city needs it from turn zero.
  defp persist_found_city!(state, player, unit) do
    territory =
      state.world
      |> Production.founding_territory(unit.tile_id)
      |> MapSet.to_list()
      |> Enum.sort()

    worked =
      case Yields.pick_worked_tile(
             %{tile_id: unit.tile_id, territory: territory, worked_tiles: []},
             state.world
           ) do
        nil -> []
        tile -> [tile]
      end

    Repo.transaction(fn ->
      {:ok, city} =
        %__MODULE__{}
        |> changeset(%{
          world_id: state.world.id,
          player_id: player.id,
          tile_id: unit.tile_id,
          name: default_city_name(state, player),
          size: 1,
          food: 0,
          territory: territory,
          worked_tiles: worked
        })
        |> Repo.insert()

      Unit |> Repo.get!(unit.id) |> Repo.delete!()

      city_map(%{city | production_items: []})
    end)
  end

  defp default_city_name(state, player) do
    count = state.cities |> Map.values() |> Enum.count(&(&1.player_id == player.id))
    "City #{count + 1}"
  end

  # -------------------------------------------------------------------
  # Worked tiles (moved from WorldServer's `do_assign_worked_tile/5`)
  # -------------------------------------------------------------------

  # `from_tile`/`to_tile` are each optionally `nil`: unassigning alone
  # drops a citizen to idle, assigning alone fills an open slot, and
  # both together is the panel's ordinary reassignment.
  @doc """
  Assign (and/or unassign) a citizen between `from_tile` and `to_tile`
  in `city_id`'s own territory. Either arg may be `nil` — see the
  moduledoc note above for the three shapes this command takes.
  """
  @spec assign_worked_tile(map(), map(), integer(), integer() | nil, integer() | nil) ::
          {:ok, map()} | {:error, atom()}
  def assign_worked_tile(state, user, city_id, from_tile, to_tile) do
    with {:ok, city} <- owned_city(state, user, city_id),
         :ok <- validate_unassign(city, from_tile),
         :ok <- validate_assign(state.world, city, from_tile, to_tile) do
      worked = city.worked_tiles |> maybe_remove(from_tile) |> maybe_add(to_tile)
      persist_worked_tiles!(city_id, worked)
      {:ok, %{state | cities: Map.put(state.cities, city_id, %{city | worked_tiles: worked})}}
    end
  end

  defp maybe_remove(tiles, nil), do: tiles
  defp maybe_remove(tiles, tile), do: List.delete(tiles, tile)

  defp maybe_add(tiles, nil), do: tiles
  defp maybe_add(tiles, tile), do: tiles ++ [tile]

  defp validate_unassign(_city, nil), do: :ok

  defp validate_unassign(city, tile) do
    if tile in city.worked_tiles, do: :ok, else: {:error, :not_worked}
  end

  defp validate_assign(_world, _city, _from_tile, nil), do: :ok

  # A `to_tile` with no paired `from_tile` grows the worked-tile count
  # by one — refused once the city is already at its population cap
  # (`changeset/2`'s `validate_worked_tiles_within_size/1` encodes the
  # same "cannot exceed size" invariant, but this write path persists
  # via a raw `Repo.update_all` that never runs the changeset, so the
  # cap has to be checked here too — issue 7509c453). A paired swap
  # (`from_tile` supplied) never changes the count, so it stays allowed
  # even at the cap.
  defp validate_assign(world, city, from_tile, tile) do
    cond do
      tile == city.tile_id -> {:error, :invalid_tile}
      tile not in city.territory -> {:error, :not_territory}
      tile in city.worked_tiles -> {:error, :already_worked}
      not Yields.workable?(Regions.terrain(world, tile)) -> {:error, :invalid_terrain}
      is_nil(from_tile) and length(city.worked_tiles) >= city.size -> {:error, :size_exceeded}
      true -> :ok
    end
  end

  defp persist_worked_tiles!(city_id, worked_tiles) do
    Repo.update_all(from(c in __MODULE__, where: c.id == ^city_id),
      set: [worked_tiles: worked_tiles]
    )
  end

  # -------------------------------------------------------------------
  # Rename (moved from WorldServer's `do_rename_city/4`)
  # -------------------------------------------------------------------

  @doc "Rename `city_id` to `name`, trimmed — refuses blank or over-length names."
  @spec rename_city(map(), map(), integer(), String.t()) :: {:ok, map()} | {:error, atom()}
  def rename_city(state, user, city_id, name) do
    with {:ok, city} <- owned_city(state, user, city_id),
         :ok <- validate_name(name) do
      trimmed = String.trim(name)
      Repo.update_all(from(c in __MODULE__, where: c.id == ^city_id), set: [name: trimmed])
      {:ok, %{state | cities: Map.put(state.cities, city_id, %{city | name: trimmed})}}
    end
  end

  defp validate_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed != "" and String.length(trimmed) <= 100, do: :ok, else: {:error, :invalid_name}
  end

  defp validate_name(_other), do: {:error, :invalid_name}

  # -------------------------------------------------------------------
  # Reads (moved from WorldServer's `player_cities/2`/`format_city/2`)
  # -------------------------------------------------------------------

  @doc "Every city `user` owns, formatted for `GameLive.CityPanel`."
  @spec player_cities(map(), map()) :: [map()]
  def player_cities(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        for {_id, city} <- state.cities,
            city.player_id == player.id,
            do: format_city(state, city)
    end
  end

  # `production` is an informational per-turn RATE (flat base + worked
  # production), separate from `queue`'s own `banked`/`cost` progress —
  # useful for a "5/turn" readout alongside the current build's bar.
  defp format_city(state, city) do
    worked_production =
      city
      |> Yields.worked_yields(state.world, state.improvements)
      |> Enum.map(& &1.production)
      |> Enum.sum()

    age = Research.age(player_research_for(state, city.player_id))

    %{
      id: city.id,
      name: city.name,
      tile_id: city.tile_id,
      size: city.size,
      food: city.food,
      food_threshold: Yields.threshold(city.size, age),
      production: Production.flat_base() + worked_production,
      queue: city.queue,
      territory: city.territory,
      worked_tiles: city.worked_tiles,
      hp: city.hp,
      defense: CityDefense.defensive_strength(city, Map.values(state.units)),
      # QA issue 1c47edff "Granary confusion" — `has_granary` was
      # tracked on the `City` schema and already fed `Yields.
      # accrue_food/3`'s math, but never made it into THIS map, the one
      # `Game.player_cities/2` actually hands to `GameLive.CityPanel` —
      # so a built Granary had no way to ever show up in the UI at all.
      has_granary: city.has_granary,
      # Story 930 — the other four buildings (Library, Ancient Walls,
      # Barracks, Water Mill); see `Buildings`'s own moduledoc.
      buildings: Map.get(city, :buildings, []),
      # Story 906 — `:free` (no badge), `:broken` (0 HP, not yet
      # entered), or `:occupied` (captured) — `Siege.status/1`'s own
      # single source of truth for `GameLive.CityPanel`'s `city-status`
      # badge.
      status: Siege.status(city),
      occupied_by_player_id: Map.get(city, :occupied_by_player_id)
    }
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer` (or reaching sideways into `Production`/`Research`),
  # matching the sibling `Rebellion.War`'s own "pure, process-unaware,
  # unit-testable with no GenServer running" contract (small private
  # helper copies rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp owned_city(state, user, city_id) do
    player = find_player(state, user.id)
    city = Map.get(state.cities, city_id)

    if is_nil(player) or is_nil(city) or city.player_id != player.id do
      {:error, :not_owner}
    else
      {:ok, city}
    end
  end

  defp player_region_tiles(world, region_id) do
    world |> Regions.partition() |> Map.fetch!(:regions) |> Map.fetch!(region_id) |> MapSet.new()
  end

  defp player_research_for(state, player_id),
    do: Map.get(state.player_research, player_id, Research.new())

  defp city_map(%__MODULE__{} = c) do
    %{
      id: c.id,
      player_id: c.player_id,
      tile_id: c.tile_id,
      name: c.name,
      size: c.size,
      food: c.food,
      territory: c.territory,
      worked_tiles: c.worked_tiles,
      hp: c.hp,
      production_halted_until: c.production_halted_until,
      has_granary: c.has_granary,
      buildings: c.buildings,
      occupied_by_player_id: c.occupied_by_player_id,
      queue: Enum.map(c.production_items, &queue_item_map/1)
    }
  end

  defp queue_item_map(%ProductionItem{} = item),
    do: %{
      id: item.id,
      type: item.type,
      banked: item.banked,
      cost: item.cost,
      position: item.position
    }

  defp camp_map(%Camp{} = c) do
    %{
      id: c.id,
      tile_id: c.tile_id,
      hp: c.hp,
      spawn_counter: c.spawn_counter,
      destroyed_at: c.destroyed_at
    }
  end
end
