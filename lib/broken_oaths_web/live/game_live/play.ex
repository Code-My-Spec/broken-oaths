defmodule BrokenOathsWeb.GameLive.Play do
  @moduledoc """
  The board — a fog-filtered globe for one player's civilization.

  Route: `/play/:id` (a `BrokenOaths.Worlds.World` id). Renders once the
  player has already joined that world (see `GameLive.Join`); a player
  with no claimed region is bounced back to the picker.

  This LiveView holds only a projection of `BrokenOaths.Game`'s live
  state: it subscribes to the world's PubSub topic, sends commands
  (`select_unit`, `queue_move`, `abandon_world`), and re-pushes the
  fog-filtered board on every diff. Per the board doctrine, there is no
  tile DOM — geometry, visibility and units travel as pushed client
  events and the canvas hook owns painting:

    * `game:window`     — `%{tiles: [[id, color, decor, tex, cx, cy, cz, cx1, cy1, cz1, ...], ...]}`,
                           fog-filtered to only known (visible ∪ explored) tiles;
                           `decor` names a billboard sprite (or nil) and `tex`
                           a ground texture, per the art-pipeline ADR
    * `game:visibility` — `%{visible: [tile_id], explored: [tile_id]}`
    * `game:units`      — `%{units: [unit]}`, fog-filtered (own units always
                           included; another player's unit only while visible)
    * `game:selected`   — `%{unit_id: id | nil}`, echoes the current selection
    * `game:path`       — `%{unit_id: id, tiles: [tile_id]}`, the selected
                           unit's remaining order path — pushed on queue, on
                           selection, and on every board refresh (empty when
                           the unit has no order)
    * `game:cities`     — `%{cities: [%{id:, name:, tile_id:, size:}]}`, the
                           player's own cities (never fog-filtered — a city
                           is only ever seen by its owner here)
    * `game:resources`  — `%{resources: [%{tile_id:, kind:}]}` (story 905),
                           bonus-resource billboards for every currently
                           known (visible ∪ explored) tile — resources are
                           visible unconditionally (no reveal tech), the same
                           fog rule as terrain itself, so this rides the same
                           `known` set `game:window` already computes rather
                           than a separate fog-gated `Game` read
    * `game:camps`      — `%{camps: [%{id:, tile_id:, hp:, warriors: [...]}]}`,
                           barbarian camps (story 892), fog-filtered by
                           `Game.camps_visible_to/2` — see that function's
                           doc for the "own region OR explored" rule; a camp
                           outside both never appears here (criterion 7546,
                           a HARD constraint)
    * `globe3d:airspace`— `%{levels: %{tile_id => 1..3}, arc: float}` (reused
                           weather layer from `BrokenOaths.Worlds.Weather`)
    * `game:alert`      — `%{message: string}` (story 895), a barbarian
                           closing within `Game.CityDefense.approach_range/0`
                           hexes of one of the player's own cities, or one
                           of their cities taking a hit — player-scoped,
                           same shape as `game:lineage` below
    * `game:discovery`  — `%{message: string}` (story 899), fired once per
                           side the turn-boundary first-contact detection
                           (`Game.Discovery`) finds a new pair — player-scoped,
                           same shape as `game:alert`/`game:lineage`
    * `game:age`        — `%{message: string}` (story 903), fired once when
                           `{:tech_completed, user_id, :bronze_working}`
                           lands for this player — player-scoped, same shape
                           as `game:alert`/`game:discovery`/`game:lineage`

  Turn number, countdown, and the selected-unit's/-city's details are each
  their own `liveview_component` (`GameLive.TurnBar`, `GameLive.UnitPanel`,
  `GameLive.CityPanel`) mounted here as children — this view stays scoped
  to board state. Selecting a unit and selecting a city are mutually
  exclusive (one side panel at a time): each clears the other.

  ## City loop (stories 878-883)

  Founding, production, worked-tile assignment, renaming, and worker
  improvements are all `BrokenOaths.Game` commands dispatched the same
  way orders are — this view holds no city logic of its own, just the
  `:cities_changed`/`:improvements_changed` broadcasts that tell it to
  re-pull `Game.player_cities/2` (mirroring `:units_changed` for units).
  `GameLive.UnitPanel` grows a Found City action (settlers) and Build
  Improvement actions (workers, gated by `Game.Improvement.allowed?/2`
  against the unit's own tile) so both panels dispatch every city-loop
  command; `GameLive.CityPanel` never reads `BrokenOaths.Game` itself.

  ## `BrokenOaths.Game` surface this view depends on

  Beyond the sanctioned reads already exposed to specs
  (`claimed_region/2`, `player_units/2`, `advance_turn/1`,
  `restart_world_server/1` — see `BrokenOathsSpex.Fixtures`), the live
  board needs:

    * `subscribe(world)` — subscribe the caller to the world's topic;
      broadcasts `{:turn_advanced, turn}` after every boundary
    * `turn_number(world)` — current turn count
    * `turn_ends_at(world)` — `DateTime` the next boundary fires, for
      `GameLive.TurnBar`'s countdown
    * `gold(world, user)` — the player's current gold
    * `visibility(world, user)` — `%{visible: [tile_id], explored: [tile_id]}`
    * `units_visible_to(world, user)` — fog-filtered unit list; each unit
      exposes at least `id`, `type`, `tile_id`, `hp`, `max_hp`, `movement`,
      `max_movement`, and `order` (`nil` or `%{target_tile:, status:, path:}`,
      status `:pending | :interrupted`, path the remaining route) — shape
      expected by `GameLive.UnitPanel` and the board's path rendering
    * `queue_move(world, user, unit_id, to_tile)` —
      `{:ok, %{path: [tile_id]}} | {:error, reason}`
    * `abandon_world(world, user)` — wipes the player's units and frees
      their region
  """

  use BrokenOathsWeb, :live_view

  alias BrokenOaths.Chat
  alias BrokenOaths.Game
  alias BrokenOaths.Game.{Camp, Improvement, Presence, Research, Yields}
  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.{Generator, Globe, Regions, Resources, Terrain, Weather}

  @default_scale 700
  @max_pitch 1.50

  # Story 892, criterion 7550 — shown once, on a player's first
  # founding only. Exact wording from `.code_my_spec/stories/stone_age.md`
  # §2.1 (the trigger itself was deferred from story 878 to here).
  @barbarian_warning "Your city attracts attention. Barbarian camps are forming in the wilderness."

  # -------------------------------------------------------------------
  # Mount
  # -------------------------------------------------------------------

  def mount(%{"id" => id}, _session, socket) do
    world = Worlds.get_world!(id)
    user = socket.assigns.current_scope.user

    case Game.claimed_region(world, user) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/play")}

      _region ->
        if connected?(socket) do
          Game.subscribe(world)
          Chat.subscribe(world, user)
          Presence.connect(world, user)
        end

        mesh = Globe.get(world.frequency)
        %{terrain: terrain_map} = Generator.generate_maps(world.seed, mesh)
        units = Game.units_visible_to(world, user)
        {yaw, pitch} = camera_on(units, mesh)

        socket =
          socket
          |> assign(
            world: world,
            user: user,
            mesh: mesh,
            terrain_map: terrain_map,
            turn: Game.turn_number(world),
            turn_ends_at: Game.turn_ends_at(world),
            gold: Game.gold(world, user),
            units: [],
            cities: [],
            camps: [],
            improvements: [],
            known_players: Game.known_players(world, user),
            selected_tile: nil,
            visible: [],
            explored: [],
            selected_unit_id: nil,
            selected_unit: nil,
            selected_order: nil,
            allowed_improvements: [],
            current_dig: nil,
            order_error: nil,
            combat_error: nil,
            selected_city_id: nil,
            selected_city: nil,
            assignable_tiles: [],
            selected_camp_id: nil,
            selected_camp: nil,
            city_error: nil,
            improvement_error: nil,
            confirm_abandon?: false,
            chat_open: false,
            chat_target_user_id: nil,
            tech_panel_open?: false,
            bronze_working_pending?: false,
            player_research: Game.player_research(world, user),
            player_stats: Game.player_stats(world, user),
            # Story 907/908: the lord's own Vassals list and, for a
            # subjugated player, their own oath — both refreshed inline
            # by every command that can change them, plus the
            # `:vassals_changed`/`:new_vassal`/`:vassalized` broadcasts.
            vassals: Game.vassals(world, user),
            vassal_status: Game.vassal_status(world, user),
            yaw: yaw,
            pitch: pitch,
            scale: @default_scale,
            page_title: world.name
          )
          |> refresh_board()

        {:ok, socket}
    end
  end

  # Story 909/910's own eligibility check (`BrokenOaths.Game.Presence.
  # online?/2`) reads off this connection's own registration dying —
  # `Presence.connect/2`'s own doc explains why a `Registry` needs no
  # explicit teardown, but disconnecting here (rather than only ever on
  # crash/monitor-driven removal) drops the registration the instant an
  # ORDINARY navigation away happens too, not just a crash.
  def terminate(_reason, socket) do
    # A socket that never actually reached the board (bounced back to
    # the picker for lacking a claimed region — see `mount/3`'s own
    # `nil ->` branch) never set `:world`/`:user` at all.
    case socket.assigns do
      %{world: world, user: user} -> Presence.disconnect(world, user)
      _other -> :ok
    end

    :ok
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  def handle_event("select_unit", %{"unit_id" => unit_id}, socket) do
    unit_id = parse_id(unit_id)
    unit = Enum.find(socket.assigns.units, &(&1.id == unit_id))

    socket =
      socket
      |> assign(
        selected_unit_id: unit_id,
        selected_unit: unit,
        selected_order: unit && unit.order,
        allowed_improvements:
          worker_allowed_improvements(socket.assigns.world, unit, socket.assigns.player_research),
        current_dig: worker_current_dig(socket.assigns.improvements, unit),
        order_error: nil,
        improvement_error: nil,
        selected_city_id: nil,
        selected_city: nil,
        selected_tile: nil,
        selected_camp_id: nil,
        selected_camp: nil
      )
      |> push_event("game:selected", %{unit_id: unit_id})
      |> push_selected_path()
      |> push_city_selection()

    {:noreply, socket}
  end

  # A left click on open ground (no unit, no owned city — the board
  # hook's `click/1` fallthrough) opens a small tile panel: terrain,
  # base yields, and any known improvement. Mutually exclusive with the
  # unit/city panels, same one-side-panel rule. Only known tiles ever
  # reach the client, so no fog check is needed here beyond membership
  # in the pushed window.
  def handle_event("select_tile", %{"tile_id" => tile_id}, socket) do
    %{world: world, improvements: improvements} = socket.assigns
    tile_id = parse_id(tile_id)
    terrain = Regions.terrain(world, tile_id)
    resource = Resources.at(world, tile_id)
    yields = Yields.tile_yield(terrain, resource)
    improvement = Enum.find(improvements, &(&1.tile_id == tile_id))

    socket =
      assign(socket,
        selected_tile: %{
          id: tile_id,
          terrain: terrain_label(terrain),
          food: yields.food,
          production: yields.production,
          improvement: improvement,
          resource: resource
        },
        selected_unit_id: nil,
        selected_unit: nil,
        selected_order: nil,
        selected_city_id: nil,
        selected_city: nil,
        selected_camp_id: nil,
        selected_camp: nil
      )
      |> push_city_selection()

    {:noreply, socket}
  end

  # A left click on one of the player's own cities (see the board hook's
  # `click/1`) opens the city panel — mutually exclusive with unit
  # selection, same one-side-panel rule as `select_unit`.
  def handle_event("select_city", %{"city_id" => city_id}, socket) do
    %{world: world, cities: cities} = socket.assigns
    city_id = parse_id(city_id)
    city = Enum.find(cities, &(&1.id == city_id))

    socket =
      assign(socket,
        selected_city_id: city_id,
        selected_city: city,
        assignable_tiles: assignable_tiles(world, city),
        city_error: nil,
        selected_unit_id: nil,
        selected_unit: nil,
        selected_tile: nil,
        selected_camp_id: nil,
        selected_camp: nil
      )
      |> push_city_selection()

    {:noreply, socket}
  end

  # QA issue 748348fe "barbarian camp issues" — a camp under siege had
  # no way to show its own HP. Same mutual-exclusivity shape as
  # `select_unit`/`select_city`/`select_tile` above (one side panel at
  # a time): a camp lives in `@camps` (already fog-filtered by
  # `Game.camps_visible_to/2`), never a fresh `Game` read.
  def handle_event("select_camp", %{"camp_id" => camp_id}, socket) do
    camp_id = parse_id(camp_id)
    camp = Enum.find(socket.assigns.camps, &(&1.id == camp_id))

    socket =
      socket
      |> assign(
        selected_camp_id: camp_id,
        selected_camp: camp,
        selected_tile: nil,
        selected_unit_id: nil,
        selected_unit: nil,
        selected_order: nil,
        selected_city_id: nil,
        selected_city: nil
      )
      |> push_city_selection()

    {:noreply, socket}
  end

  # QA issue e51a31be "UI issues" — the right-side detail pane had no
  # dismiss affordance. Every panel's own close (X) button routes here;
  # it resets the exact same selection assigns `mount/3` starts with,
  # and echoes the clear back to the client the same way every OTHER
  # selection-changing handler already does (`"game:selected"` with a
  # nil unit id clears the board's own selection ring/path — see the
  # `.Board` hook's own `"game:selected"` handler; `push_city_selection/1`
  # clears the territory border/worked-tile highlight the same way).
  def handle_event("clear_selection", _params, socket) do
    socket =
      socket
      |> assign(
        selected_tile: nil,
        selected_unit_id: nil,
        selected_unit: nil,
        selected_order: nil,
        allowed_improvements: [],
        current_dig: nil,
        selected_city_id: nil,
        selected_city: nil,
        assignable_tiles: [],
        selected_camp_id: nil,
        selected_camp: nil
      )
      |> push_event("game:selected", %{unit_id: nil})
      |> push_city_selection()

    {:noreply, socket}
  end

  # Founding trades the settler for a working size-1 city immediately —
  # no turn boundary required (story 878). The settler's disappearance
  # and the new city both arrive back through the :units_changed /
  # :cities_changed broadcast this same call triggers.
  # phx-value-* params arrive as STRINGS from real DOM buttons but as
  # native integers from specs' render_hook — every id must go through
  # parse_id/1 before touching Game's integer-keyed state (QA issues
  # 1574d956 / a1c8741d: the Found City and production catalog buttons
  # were dead because these three handlers skipped the parse).
  def handle_event("found_city", %{"unit_id" => unit_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.found_city(world, user, parse_id(unit_id)) do
      :ok ->
        {:noreply, socket |> assign(city_error: nil) |> maybe_flash_barbarian_warning()}

      {:error, reason} ->
        {:noreply, assign(socket, city_error: city_error_message(reason))}
    end
  end

  def handle_event("queue_production", %{"city_id" => city_id, "item" => item}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.queue_production(world, user, parse_id(city_id), item) do
      :ok -> {:noreply, assign(socket, city_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, city_error: city_error_message(reason))}
    end
  end

  def handle_event(
        "cancel_production_item",
        %{"city_id" => city_id, "item_id" => item_id},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.cancel_production_item(world, user, parse_id(city_id), parse_id(item_id)) do
      :ok -> {:noreply, assign(socket, city_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, city_error: city_error_message(reason))}
    end
  end

  def handle_event(
        "reorder_production_item",
        %{"city_id" => city_id, "item_id" => item_id},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.reorder_production_item(world, user, parse_id(city_id), parse_id(item_id)) do
      :ok -> {:noreply, assign(socket, city_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, city_error: city_error_message(reason))}
    end
  end

  # `from_tile_id`/`to_tile_id` are each optional (see `Game.assign_worked_tile/5`):
  # a plain click, unlike a spec's render_hook, only ever supplies one of
  # the two (unwork vs. work), so a missing key means nil, not an error.
  def handle_event("assign_worked_tile", params, socket) do
    %{world: world, user: user} = socket.assigns
    city_id = parse_id(params["city_id"])
    from_tile = parse_id(params["from_tile_id"])
    to_tile = parse_id(params["to_tile_id"])

    case Game.assign_worked_tile(world, user, city_id, from_tile, to_tile) do
      :ok -> {:noreply, assign(socket, city_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, city_error: city_error_message(reason))}
    end
  end

  def handle_event("rename_city", %{"city" => %{"name" => name}}, socket) do
    %{world: world, user: user, selected_city_id: city_id} = socket.assigns

    case Game.rename_city(world, user, city_id, name) do
      :ok -> {:noreply, assign(socket, city_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, city_error: city_error_message(reason))}
    end
  end

  def handle_event("start_improvement", %{"unit_id" => unit_id, "kind" => kind}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.start_improvement(world, user, parse_id(unit_id), kind) do
      :ok ->
        # Refresh inline (not just via the async :improvements_changed
        # broadcast) so the dig-progress badge appears in the same
        # render as the click — issue b5cc4ae9.
        {:noreply, socket |> assign(improvement_error: nil) |> refresh_board()}

      {:error, reason} ->
        {:noreply, assign(socket, improvement_error: improvement_error_message(reason))}
    end
  end

  # QA issue 8aa2c571 — a worker mid-dig had no way to back out of it.
  # Same inline-refresh pattern as `start_improvement` above: the
  # dig-progress badge (and its Cancel button) must disappear in the
  # SAME render as the click, not wait on the async broadcast.
  def handle_event("cancel_improvement", %{"unit_id" => unit_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.cancel_improvement(world, user, parse_id(unit_id)) do
      :ok ->
        {:noreply, socket |> assign(improvement_error: nil) |> refresh_board()}

      {:error, reason} ->
        {:noreply, assign(socket, improvement_error: improvement_error_message(reason))}
    end
  end

  # Right-clicks arrive as the clicked point on the unit sphere, not a
  # tile id: the client's tile window is fog-filtered, so it cannot name
  # a tile it has never seen. The server resolves which tile the player
  # aimed at — orders into and through the fog of war are legal, and no
  # hidden tile data ever travels to the client to make them so.
  def handle_event("queue_move", %{"unit_id" => unit_id, "to_point" => [x, y, z]}, socket)
      when is_number(x) and is_number(y) and is_number(z) do
    to_tile = nearest_tile(socket.assigns.mesh, {x, y, z})
    handle_event("queue_move", %{"unit_id" => unit_id, "to_tile" => to_tile}, socket)
  end

  # phx-value-* params arrive as STRINGS from real DOM buttons but as
  # native integers from specs' render_hook — every id must go through
  # parse_id/1 before touching Game's integer-keyed state (same QA
  # issue class documented on found_city/2 above; queue_move had the
  # identical gap — a string unit_id silently failed as :not_owner,
  # since `Map.get(state.units, unit_id)` never matches an integer key
  # against a string).
  def handle_event("queue_move", %{"unit_id" => unit_id, "to_tile" => to_tile}, socket) do
    %{world: world, user: user} = socket.assigns
    unit_id = parse_id(unit_id)

    case Game.queue_move(world, user, unit_id, to_tile) do
      {:ok, %{path: path}} ->
        socket =
          socket
          |> assign(order_error: nil)
          |> push_event("game:path", %{unit_id: unit_id, tiles: path})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, order_error: order_error_message(reason))}
    end
  end

  # Resolves immediately, like queue_move — the result carries this
  # turn's damage_dealt/damage_taken (story 891, criterion 7540), which
  # this handler pushes straight back to the attacker's own view rather
  # than waiting on the broadcast every other mutation relies on
  # (mirroring queue_move's direct "game:path" push above).
  def handle_event("attack", %{"unit_id" => unit_id, "target_unit_id" => target_unit_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.attack(world, user, parse_id(unit_id), parse_id(target_unit_id)) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: combat_error_message(reason))}
    end
  end

  # Story 894: attacking a barbarian camp reuses the "attack" hook, with
  # `target_camp_id` instead of `target_unit_id` (a camp is not a
  # `Game.Unit`) — same immediate-resolution, direct-push shape as the
  # unit-target clause above. `damage_taken` is always 0 (camps never
  # counter-attack, see `Game.Combat.camp_damage/2`).
  def handle_event("attack", %{"unit_id" => unit_id, "target_camp_id" => target_camp_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.attack_camp(world, user, parse_id(unit_id), parse_id(target_camp_id)) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: combat_error_message(reason))}
    end
  end

  # Story 895: attacking a city reuses the "attack" hook, with
  # `target_city_id` instead of `target_unit_id`/`target_camp_id` — same
  # immediate-resolution, direct-push shape as both clauses above.
  # `damage_taken` is the attacker's own counter-attack damage from the
  # city's strongest garrisoned defender (0 if undefended).
  def handle_event("attack", %{"unit_id" => unit_id, "target_city_id" => target_city_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.attack_city(world, user, parse_id(unit_id), parse_id(target_city_id)) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: combat_error_message(reason))}
    end
  end

  # Story 906: the conqueror's own execute-or-release choice for a
  # captured city's fallen garrison — sent once the conqueror has
  # already walked onto the broken city's own tile. Matched on the
  # literal `"choice"` value (never an atom built from user input) so
  # an unrecognized string is simply refused, not converted.
  def handle_event(
        "resolve_garrison_fate",
        %{"city_id" => city_id, "choice" => "release"},
        socket
      ) do
    resolve_garrison_fate(socket, city_id, :release)
  end

  def handle_event(
        "resolve_garrison_fate",
        %{"city_id" => city_id, "choice" => "execute"},
        socket
      ) do
    resolve_garrison_fate(socket, city_id, :execute)
  end

  # Story 907: the fresh vassal's own secret Hidden Agenda pick,
  # closing the Oath screen — matched on the literal agenda string (the
  # same "never build an atom from raw user input" posture
  # `resolve_garrison_fate` above already takes); an unrecognized
  # string falls through to `Game.choose_hidden_agenda/3` with an
  # `:invalid` atom, which `Ecto.Enum` refuses as a changeset error
  # rather than crashing.
  def handle_event("choose_hidden_agenda", %{"agenda" => agenda}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.choose_hidden_agenda(world, user, parse_agenda(agenda)) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Story 908: the lord-set, per-vassal tribute rate lever — `"rate"`
  # arrives as a 0-100 percentage string ("50"), converted to the
  # 0.0-1.0 fraction `Vassalage.tribute_rate` stores.
  def handle_event(
        "set_tribute_rate",
        %{"vassal_user_id" => vassal_user_id, "rate" => rate},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.set_tribute_rate(world, user, parse_id(vassal_user_id), parse_percent(rate)) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Story 908: the lord's own call to arms against a third player —
  # `"share"` arrives as the pledged fraction (0, 1] directly, not a
  # percentage (mirrors `Levy.pledged_share`'s own scale).
  def handle_event(
        "issue_levy",
        %{"vassal_user_id" => vassal_user_id, "target_user_id" => target_user_id, "share" => share},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.issue_levy(
           world,
           user,
           parse_id(vassal_user_id),
           parse_id(target_user_id),
           parse_fraction(share)
         ) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("answer_levy", %{"lord_user_id" => lord_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.answer_levy(world, user, parse_id(lord_user_id)) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("refuse_levy", %{"lord_user_id" => lord_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.refuse_levy(world, user, parse_id(lord_user_id)) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Story 899, criterion 7601: a Known Players row's "chat-link"
  # affordance opens the chat panel straight onto that contact's
  # thread — full conversation-loading behavior lands with
  # `GameLive.ChatPanel` (story 900); this just carries which contact
  # was picked, in `:chat_target_user_id`, into that component's own
  # assigns.
  def handle_event("open_chat", %{"user_id" => user_id}, socket) do
    {:noreply, assign(socket, chat_open: true, chat_target_user_id: parse_id(user_id))}
  end

  def handle_event("abandon_world", _params, socket) do
    {:noreply, assign(socket, confirm_abandon?: true)}
  end

  def handle_event("abandon_cancel", _params, socket) do
    {:noreply, assign(socket, confirm_abandon?: false)}
  end

  def handle_event("abandon_confirm", _params, socket) do
    %{world: world, user: user} = socket.assigns
    :ok = Game.abandon_world(world, user)
    {:noreply, push_navigate(socket, to: ~p"/play")}
  end

  # Story 902: `GameLive.TechPanel` is presentational (no `phx-target`,
  # same bubbling pattern as `CityPanel`/`UnitPanel`) — every one of its
  # clicks lands here. `"select_research"` commits immediately for every
  # tech EXCEPT Bronze Working, which instead raises the confirm warning
  # (`bronze_working_pending?`) the panel renders; only
  # `"bronze_working_confirm"` actually calls `Game.set_research/3` for
  # it (criterion 7630). Every commit re-pulls `player_research` inline
  # rather than waiting on the `:research_changed` broadcast (below) —
  # same "refresh inline so the click's own render sees it" reasoning
  # `"start_improvement"` already documents for `improvement_error`.
  def handle_event("toggle_tech_panel", _params, socket) do
    {:noreply, assign(socket, tech_panel_open?: !socket.assigns.tech_panel_open?)}
  end

  def handle_event("select_research", %{"tech" => "bronze_working"}, socket) do
    {:noreply, assign(socket, bronze_working_pending?: true)}
  end

  def handle_event("select_research", %{"tech" => tech}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.set_research(world, user, parse_tech(tech)) do
      :ok -> {:noreply, refresh_research(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("bronze_working_confirm", _params, socket) do
    %{world: world, user: user} = socket.assigns
    :ok = Game.set_research(world, user, :bronze_working)
    {:noreply, socket |> assign(bronze_working_pending?: false) |> refresh_research()}
  end

  def handle_event("bronze_working_cancel", _params, socket) do
    {:noreply, assign(socket, bronze_working_pending?: false)}
  end

  # -------------------------------------------------------------------
  # Live updates
  # -------------------------------------------------------------------

  # WorldServer broadcasts this after every boundary — connected players
  # see the new turn and any resolved moves with no refresh (story 874).
  # Story 902: every tick banks science toward `current_research` too
  # (`Turn.tick/1` phase 8), so `player_research` is re-pulled here
  # alongside the board.
  def handle_info({:turn_advanced, turn}, socket) do
    %{world: world} = socket.assigns

    socket =
      socket
      |> assign(turn: turn, turn_ends_at: Game.turn_ends_at(world))
      |> refresh_board()
      |> refresh_research()

    {:noreply, socket}
  end

  # Story 902: `WorldServer` broadcasts this world-wide after every
  # `Game.set_research/3` — same "every connected view re-pulls its own
  # state" pattern as `:units_changed`/`:cities_changed`. This view's own
  # `"select_research"`/`"bronze_working_confirm"` handlers already
  # refresh inline (see their own doc), so this mostly matters for a
  # second connected tab on the same account.
  def handle_info(:research_changed, socket) do
    {:noreply, refresh_research(socket)}
  end

  # Any board mutation (a queued order executing immediately, a join, an
  # abandon) broadcasts :units_changed — every connected view re-pulls
  # the fog-filtered board so units move live, mid-turn.
  def handle_info(:units_changed, socket) do
    {:noreply, refresh_board(socket)}
  end

  # Founding, production, worked-tile assignment, and renaming all
  # broadcast :cities_changed — re-pull cities the same way :units_changed
  # re-pulls units, so the panel and the map stay live without a refresh.
  def handle_info(:cities_changed, socket) do
    {:noreply, refresh_board(socket)}
  end

  # A worker starting/advancing/finishing a dig broadcasts
  # :improvements_changed — a completed improvement changes a city's
  # worked-tile yields (production/food), so cities are re-pulled too.
  def handle_info(:improvements_changed, socket) do
    {:noreply, refresh_board(socket)}
  end

  # `Turn.tick/1` pairs every completed production item with its own
  # `{:unit_spawned, spawn_event}` broadcast (see `WorldServer.
  # materialize_spawns/2`) alongside the tick's `{:turn_advanced, turn}`
  # — the same message batch this view already refreshes on. The new
  # unit arrives through that refresh's `Game.units_visible_to/2` call,
  # so this is a safe no-op today; it exists so an unhandled event never
  # crashes the LiveView (a future "your Warrior is ready" toast would
  # hook in here).
  def handle_info({:unit_spawned, _spawn_event}, socket) do
    {:noreply, socket}
  end

  # Story 903: completing Bronze Working is the one tech completion
  # that gets its own one-shot notification (the story's own
  # acceptance text) — player-scoped, same `"game:<name>"` + `message`
  # dispatch convention as `game:alert`/`game:discovery`/`game:lineage`
  # below. `Turn.tick/1` orders `{:tech_completed, ...}` AFTER
  # `{:turn_advanced, turn}` in the same event batch (`Turn.tick/1`'s
  # own moduledoc), so `player_research` (and therefore `AgePanel`'s
  # own `Research.age/1` read) is already refreshed to Bronze Age by
  # the time this fires — no separate refresh needed here.
  def handle_info({:tech_completed, user_id, :bronze_working}, socket) do
    if user_id == socket.assigns.user.id do
      {:noreply,
       push_event(socket, "game:age", %{
         message: "You have entered the Bronze Age! New units and buildings unlocked."
       })}
    else
      {:noreply, socket}
    end
  end

  # Story 902: `Turn.tick/1`'s science-accrual phase (phase 8) pairs a
  # tech reaching its cost with its own `{:tech_completed, user_id,
  # tech}` broadcast, alongside the SAME tick's `{:turn_advanced, turn}`
  # this view already refreshes `player_research` on (see that handler's
  # own doc) — so, like `{:unit_spawned, _}` above, every OTHER tech
  # completion is a safe no-op; it exists so an unhandled event never
  # crashes the LiveView (a future "Animal Husbandry researched!" toast
  # would hook in here).
  def handle_info({:tech_completed, _user_id, _tech}, socket) do
    {:noreply, socket}
  end

  # `Turn.tick/1`'s heir-succession phase (story 896, criterion 7573)
  # broadcasts this world-wide, same as every other tick event — every
  # connected player's view receives it and only the one whose lord
  # just got a successor pushes the notification.
  def handle_info({:lineage_continued, user_id, message}, socket) do
    if user_id == socket.assigns.user.id do
      {:noreply, push_event(socket, "game:lineage", %{message: message})}
    else
      {:noreply, socket}
    end
  end

  # Story 895: `WorldServer` pushes this world-wide for both the
  # approach alert (a threat closing within `CityDefense.approach_range/0`
  # hexes of a city) and the under-attack alert (a city taking a hit) —
  # same player-scoped shape as `:lineage_continued` above, just a
  # `"game:alert"` push instead of `"game:lineage"`.
  def handle_info({:city_alert, user_id, message}, socket) do
    if user_id == socket.assigns.user.id do
      {:noreply, push_event(socket, "game:alert", %{message: message})}
    else
      {:noreply, socket}
    end
  end

  # Story 899: `WorldServer`'s turn-boundary first-contact detection
  # (`Game.Discovery`) broadcasts this world-wide, once per side of a
  # newly-discovered pair — same player-scoped shape as
  # `:lineage_continued`/`:city_alert` above, just a `"game:discovery"`
  # push instead.
  def handle_info({:discovery, user_id, message}, socket) do
    if user_id == socket.assigns.user.id do
      {:noreply, push_event(socket, "game:discovery", %{message: message})}
    else
      {:noreply, socket}
    end
  end

  # Story 900: `Chat.subscribe/2` (called at mount, above) puts THIS
  # view's own process on `user`'s per-world chat inbox topic — a
  # message lands here the instant `Chat.send_message/4` delivers it to
  # either side of a conversation this player is part of. Forwarded
  # into `GameLive.ChatPanel`'s own `update/2` via `send_update/2`
  # (a component has no mailbox of its own) rather than handled here,
  # since the panel — not this view — owns the contact list, unread
  # counts, and the open thread's message window (see that module's
  # own "Real-time delivery" doc).
  def handle_info({:chat_message, message}, socket) do
    send_update(BrokenOathsWeb.GameLive.ChatPanel, id: "chat-panel", new_message: message)
    {:noreply, socket}
  end

  # Story 900: `GameLive.ChatPanel` owns its own open/closed state
  # locally, but this view still needs to know it changed so it can
  # hide `GameLive.KnownPlayersPanel` while the chat panel's own
  # contact list is showing (see `ChatPanel`'s own "Talking back to
  # Play" doc for why the two must never both render a `"known-player-
  # ID"` row at once).
  def handle_info({:chat_open_changed, open?}, socket) do
    {:noreply, assign(socket, chat_open: open?)}
  end

  # Story 901: `WorldServer` broadcasts this world-wide after every
  # successful `Game.propose_alliance/3`/`Game.accept_alliance/3` —
  # forwarded straight into `GameLive.AlliancePanel` via `send_update/2`
  # (same "component has no mailbox of its own" pattern `ChatPanel`'s
  # own `{:chat_message, message}` forwarding already establishes), so
  # the OTHER party to a proposal sees it live rather than waiting on
  # their next turn-boundary refresh.
  def handle_info(:alliances_changed, socket) do
    send_update(BrokenOathsWeb.GameLive.AlliancePanel, id: "alliance-panel", refresh: true)
    {:noreply, socket}
  end

  # Story 906/907: pushed straight to the FRESH VASSAL's own session the
  # instant their last free city falls — refreshes `:vassal_status`
  # inline (so the Oath screen/`vassal-status` badge render in the same
  # update) and pushes the one-shot toast, same player-scoped shape as
  # `:city_alert`/`:discovery`/`:lineage_continued` above.
  def handle_info({:vassalized, user_id, message}, socket) do
    if user_id == socket.assigns.user.id do
      socket = socket |> refresh_vassalage() |> push_event("game:vassalized", %{message: message})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Story 907: the lord's own half of "both players notified" — pushed
  # straight to the LORD's own session, refreshing `:vassals` inline so
  # the new `vassal-row` appears without waiting on a reconnect.
  def handle_info({:new_vassal, user_id, vassal_user_id, message}, socket) do
    if user_id == socket.assigns.user.id do
      socket =
        socket
        |> refresh_vassalage()
        |> push_event("game:new_vassal", %{vassal_user_id: vassal_user_id, message: message})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Story 908: every OTHER Vassalage/Levy mutation (a raised tribute
  # rate, an issued/answered/refused call to arms) broadcasts this
  # world-wide — every connected view re-pulls both its own
  # `:vassals`/`:vassal_status` reads, the same "every connected view
  # re-pulls its own state" pattern `:cities_changed`/`:research_changed`
  # already establish.
  def handle_info(:vassals_changed, socket) do
    {:noreply, refresh_vassalage(socket)}
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  # Camera aimed at the centroid of the player's own units at spawn
  # (criterion: returning player resumes with the camera on their
  # civilization). Never recomputed after mount — later refreshes must
  # not yank the view out from under the player.
  defp camera_on([], _mesh), do: {0.0, 0.0}

  defp camera_on(units, mesh) do
    {sx, sy, sz} =
      units
      |> Enum.map(fn unit -> Globe.tile(mesh, unit.tile_id).center end)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {x, y, z}, {ax, ay, az} -> {ax + x, ay + y, az + z} end)

    case :math.sqrt(sx * sx + sy * sy + sz * sz) do
      norm when norm > 0.0 ->
        {:math.atan2(sy / norm, sx / norm), :math.asin(clamp(sz / norm))}

      _ ->
        {0.0, 0.0}
    end
  end

  defp clamp(z), do: max(-1.0, min(1.0, z))

  # "First founding" is read back from the real surface (a player's own
  # city count) rather than threading a flag through `Game.found_city/3`'s
  # return value — founding always adds exactly one city, so having
  # exactly one right after a successful founding IS "this was the
  # first" (story 892, criterion 7550: shown once, never on a second or
  # later founding).
  # Flash assigns persist for the life of the LiveView connection, not
  # just the render right after `put_flash/3` — a second (or later)
  # founding on this same connection would otherwise still show the
  # first founding's warning, since nothing else in this view ever
  # clears it. A non-first founding explicitly clears it instead of
  # merely skipping the `put_flash` call (story 892, criterion 7550:
  # "does not repeat").
  defp maybe_flash_barbarian_warning(socket) do
    %{world: world, user: user} = socket.assigns

    if length(Game.player_cities(world, user)) == 1 do
      put_flash(socket, :info, @barbarian_warning)
    else
      clear_flash(socket, :info)
    end
  end

  # Single source of truth for "what does this player currently know":
  # re-fetches fog-filtered units + visibility + gold and pushes the
  # whole board state down. Called at mount, on every turn boundary,
  # and on every `:units_changed` broadcast — including the ones an
  # "attack"/"attack_camp" bounty or camp-destroy reward fires, so the
  # gold badge never lags behind a combat-driven change (story 893/894
  # criteria 7557/7560; before either existed, nothing but a turn
  # boundary could ever change gold, so this refresh never needed it).
  defp refresh_board(socket) do
    %{
      world: world,
      user: user,
      selected_unit_id: selected_unit_id,
      selected_city_id: selected_city_id,
      selected_camp_id: selected_camp_id
    } = socket.assigns

    units = Game.units_visible_to(world, user)
    cities = Game.player_cities(world, user)
    camps = Game.camps_visible_to(world, user)
    improvements = Game.improvements_visible_to(world, user)
    %{visible: visible, explored: explored} = Game.visibility(world, user)
    selected_unit = selected_unit_id && Enum.find(units, &(&1.id == selected_unit_id))
    selected_city = selected_city_id && Enum.find(cities, &(&1.id == selected_city_id))
    # QA issue 748348fe: a camp under siege stays selected across the
    # refresh a successful attack triggers (`:units_changed`), the same
    # "re-find by id in the fresh list" pattern `selected_unit`/
    # `selected_city` already use — a destroyed camp simply drops out of
    # `camps_visible_to/2`'s own list, so this naturally clears back to
    # `nil` the instant the camp falls, with no separate teardown needed.
    selected_camp = selected_camp_id && Enum.find(camps, &(&1.id == selected_camp_id))
    # Story 904: `science_per_turn` is derived from `cities` (`Research.
    # science_per_turn/1`, `2 * size` per city) — re-pulled here, not
    # just on `refresh_research/1`'s own turn-boundary/research-change
    # triggers, so founding a city updates the progress panel's science
    # figure in the SAME refresh that already re-pulls `cities`, with no
    # turn boundary required (criterion 7639).
    player_research = Game.player_research(world, user)

    socket
    |> assign(
      gold: Game.gold(world, user),
      units: units,
      cities: cities,
      camps: camps,
      improvements: improvements,
      visible: visible,
      explored: explored,
      selected_unit: selected_unit,
      selected_order: selected_unit && selected_unit.order,
      allowed_improvements: worker_allowed_improvements(world, selected_unit, player_research),
      current_dig: worker_current_dig(improvements, selected_unit),
      selected_city: selected_city,
      assignable_tiles: assignable_tiles(world, selected_city),
      selected_camp: selected_camp,
      known_players: Game.known_players(world, user),
      player_stats: Game.player_stats(world, user),
      player_research: player_research
    )
    |> push_board_state()
    |> push_selected_path()
    |> push_city_selection()
  end

  # Story 902: single source of truth for `player_research`, the same
  # "re-fetch on every signal" status `refresh_board/1` gives the rest
  # of the board — called at mount, on every turn boundary (science
  # accrues each tick), on the `:research_changed` broadcast, and
  # inline by every `TechPanel`-bubbled event that changes it.
  defp refresh_research(socket) do
    %{world: world, user: user} = socket.assigns
    assign(socket, player_research: Game.player_research(world, user))
  end

  # `TechPanel`'s `phx-value-tech` arrives as a string — `Research`'s
  # own catalog is a fixed, compile-time set of atoms, so
  # `String.to_existing_atom/1` is always safe for a legitimate tech
  # name (same safety argument `WorldServer.player_research_map/1`
  # already makes for `banked_science`'s keys); anything else becomes
  # an atom `Research.set_research/2` is guaranteed to refuse as
  # `:invalid_tech`.
  defp parse_tech(tech) when is_atom(tech), do: tech

  defp parse_tech(tech) when is_binary(tech) do
    String.to_existing_atom(tech)
  rescue
    ArgumentError -> :invalid_tech
  end

  # A queued order's remaining route renders whenever its unit is
  # selected — re-pushed on every refresh so the line shrinks as
  # movement consumes steps and disappears on arrival (story 875 rule).
  defp push_selected_path(socket) do
    case socket.assigns.selected_unit do
      nil ->
        socket

      unit ->
        tiles = (unit.order && unit.order.path) || []
        push_event(socket, "game:path", %{unit_id: unit.id, tiles: tiles})
    end
  end

  # Story 759d02c8/0b8a75e4 (v0.2.1 playtest) — Civ-style territory
  # border + worked-tile highlight for whichever city is currently
  # selected, so a city panel's raw "Tile N" rows correspond to
  # something visible on the board (issue 0b8a75e4's own ask). Called
  # from every selection-changing handler (including to no city, which
  # clears the render) and again at the end of every `refresh_board/1`
  # so growth/worked-tile changes redraw the border live while the
  # panel stays open. Deliberately scoped to the ONE selected city,
  # never every city on the board — the "keep it performant"
  # requirement both issues call out.
  #
  # Content-diffed against the last-pushed value, the SAME idiom (and
  # the same reason — QA issue dbcbd478) `push_camps/2`/
  # `push_improvements/2`/`push_resources/2` already establish: every
  # `refresh_board/1` calls this unconditionally, including the common
  # case of "nothing is selected" — without the diff, that would queue
  # a fresh no-op "game:city_selection" push on EVERY turn boundary/
  # units-changed refresh, sitting in a spec's mailbox ahead of the
  # next MEANINGFUL push the way an undiffed camps push once did.
  defp push_city_selection(socket) do
    payload =
      case socket.assigns.selected_city do
        nil ->
          %{territory: [], worked_tiles: []}

        city ->
          %{
            territory: city.territory,
            worked_tiles: Enum.uniq([city.tile_id | city.worked_tiles])
          }
      end

    last = Map.get(socket.assigns, :last_city_selection)

    cond do
      payload == last ->
        socket

      payload.territory == [] and (is_nil(last) or last.territory == []) ->
        socket

      true ->
        socket
        |> assign(:last_city_selection, payload)
        |> push_event("game:city_selection", payload)
    end
  end

  defp push_board_state(socket) do
    %{mesh: mesh, terrain_map: terrain_map, world: world} = socket.assigns

    %{units: units, cities: cities, camps: camps, visible: visible, explored: explored} =
      socket.assigns

    improvements = Map.get(socket.assigns, :improvements, [])

    known = Enum.uniq(visible ++ explored)
    tiles = Enum.map(known, &tile_row(&1, mesh, terrain_map))
    levels = Weather.map(world.seed, mesh)

    socket
    |> push_event("game:window", %{tiles: tiles})
    |> push_event("game:visibility", %{visible: visible, explored: explored})
    |> push_event("game:units", %{units: units})
    |> push_event("game:cities", %{cities: Enum.map(cities, &city_marker/1)})
    |> push_camps(camps)
    |> push_improvements(improvements)
    |> push_resources(known_resources(known, world))
    |> push_event("globe3d:airspace", %{
      levels: levels,
      arc: Float.round(1.1071 / mesh.frequency, 5)
    })
  end

  # Bonus-resource billboards (story 905) for every currently KNOWN
  # tile — resources are visible from the first look, unconditionally
  # (criterion 7649), so this reads off the very same `known` set
  # `tile_row/3` already iterates rather than a separate fog-gated
  # `Game` read the way camps/improvements need.
  defp known_resources(known, world) do
    for tile_id <- known,
        resource = Resources.at(world, tile_id),
        resource != nil,
        do: %{tile_id: tile_id, kind: resource}
  end

  # Content-diffed against the last-pushed value: refresh_board/1 runs
  # on every turn boundary and unit change, but an unchanged camp list
  # must NOT re-queue an identical push — a stale duplicate sitting in
  # a spec's mailbox is matched ahead of the next MEANINGFUL push by
  # `assert_push_event` (QA issue dbcbd478).
  #
  # The empty-payload case is NOT a blanket skip, despite camps
  # genuinely starting out empty (every mount pushes SOME board state
  # even before the player's ever founded a city — story 892) and
  # despite an empty snapshot being reachable again for real once a
  # player's last visible camp is destroyed (story 894 criterion
  # 7560): only "nothing has EVER been known" (no prior push, or the
  # prior push was already empty) is the mount-time no-op that avoids
  # sitting in a spec's mailbox ahead of the first MEANINGFUL push —
  # a KNOWN-nonempty set collapsing to empty is itself a real change
  # the client must still hear about (the same way "game:cities"/
  # "game:units" would push an emptied list unconditionally), so that
  # case still pushes even though the new payload is `[]`.
  defp push_camps(socket, camps) do
    last = Map.get(socket.assigns, :last_camps)

    cond do
      camps == last ->
        socket

      camps == [] and last in [nil, []] ->
        socket

      true ->
        socket
        |> assign(:last_camps, camps)
        |> push_event("game:camps", %{camps: camps})
    end
  end

  # Same content-diff idiom as camps (including the "empty is only a
  # no-op when nothing was EVER known" refinement above), for the same
  # mailbox reason.
  defp push_improvements(socket, improvements) do
    last = Map.get(socket.assigns, :last_improvements)

    cond do
      improvements == last ->
        socket

      improvements == [] and last in [nil, []] ->
        socket

      true ->
        socket
        |> assign(:last_improvements, improvements)
        |> push_event("game:improvements", %{improvements: improvements})
    end
  end

  # Same content-diff idiom as camps/improvements, for the same
  # mailbox reason — the resource set only ever changes as fog reveals
  # new tiles (resources themselves never move or disappear).
  defp push_resources(socket, resources) do
    last = Map.get(socket.assigns, :last_resources)

    cond do
      resources == last ->
        socket

      resources == [] and last in [nil, []] ->
        socket

      true ->
        socket
        |> assign(:last_resources, resources)
        |> push_event("game:resources", %{resources: resources})
    end
  end

  # The board only needs enough to place and label a billboard —
  # territory/queue/food stay in the CityPanel assign, not the client.
  defp city_marker(city), do: Map.take(city, [:id, :name, :tile_id, :size])

  # "Grassland Hills · Woods" — base, then relief when not flat, then
  # feature when present.
  defp terrain_label(%Terrain{base: base, relief: relief, feature: feature}) do
    [base, relief != :flat && relief, feature]
    |> Enum.filter(& &1)
    |> Enum.map_join(" · ", &(&1 |> to_string() |> String.capitalize()))
  end

  defp improvement_summary(%{kind: kind, status: :complete}),
    do: "#{kind |> to_string() |> String.capitalize()} (complete)"

  defp improvement_summary(%{kind: kind, status: :pillaged}),
    do: "#{kind |> to_string() |> String.capitalize()} (pillaged — a worker repairs it in 1 turn)"

  defp improvement_summary(%{kind: kind, status: :building, progress: progress}),
    do: "#{kind |> to_string() |> String.capitalize()} under construction (#{progress} banked)"

  # Story 905, criterion 7649 — a resource is visible unconditionally,
  # the instant the tile itself is looked at (no reveal tech, matching
  # `civ6_resources.md` §3.5's "bonus resources have no reveal-tech").
  defp resource_label(:cattle), do: "Cattle"
  defp resource_label(:sheep), do: "Sheep"
  defp resource_label(:wheat), do: "Wheat"
  defp resource_label(:stone), do: "Stone"

  # Compact row for the client painter:
  # [id, color, decor, tex, cx, cy, cz, corner1x, corner1y, corner1z, ...]
  defp tile_row(tile_id, mesh, terrain_map) do
    tile = Globe.tile(mesh, tile_id)
    terrain = Map.get(terrain_map, tile_id)
    {cx, cy, cz} = tile.center
    corners = Enum.flat_map(tile.corners, fn {x, y, z} -> [round4(x), round4(y), round4(z)] end)

    [
      tile.id,
      Terrain.color(terrain),
      Terrain.decor(terrain),
      Terrain.texture(terrain),
      round4(cx),
      round4(cy),
      round4(cz) | corners
    ]
  end

  defp round4(f), do: Float.round(f, 4)

  # The mesh tile whose center is nearest the given unit-sphere point
  # (max dot product). Linear over the mesh — ~29k tiles at f=54, a few
  # ms once per right-click.
  defp nearest_tile(mesh, {x, y, z}) do
    {id, _tile} =
      Enum.max_by(mesh.tiles, fn {_id, tile} ->
        {cx, cy, cz} = tile.center
        cx * x + cy * y + cz * z
      end)

    id
  end

  defp order_error_message(:not_owner), do: "You don't control that unit."
  defp order_error_message(:occupied), do: "Another unit already holds that tile."
  defp order_error_message(:impassable), do: "That terrain can't be crossed."
  defp order_error_message(:unreachable), do: "There's no path there."
  defp order_error_message(_other), do: "That order can't be queued."

  defp combat_error_message(:not_owner), do: "You don't control that unit."
  defp combat_error_message(:invalid_target), do: "That target no longer exists."
  defp combat_error_message(:out_of_movement), do: "That unit has no movement left to attack."
  defp combat_error_message(:not_adjacent), do: "That target is out of range."

  defp combat_error_message(:not_hostile),
    do: "Stone Age players cannot fight each other — only barbarians can be attacked."

  defp combat_error_message(:own_city), do: "You can't attack your own city."

  defp combat_error_message(:not_military),
    do: "Only military units can lay siege to a city — civilians cannot besiege."

  defp combat_error_message(_other), do: "That attack can't be ordered."

  # -------------------------------------------------------------------
  # Vassalage / Tribute helpers (stories 906/907/908)
  # -------------------------------------------------------------------

  defp resolve_garrison_fate(socket, city_id, choice) do
    %{world: world, user: user} = socket.assigns

    case Game.resolve_garrison_fate(world, user, parse_id(city_id), choice) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:noreply, assign(socket, combat_error: combat_error_message(reason))}
    end
  end

  # Single source of truth for `:vassals`/`:vassal_status` — re-pulled
  # inline by every command that can change either (mirrors
  # `refresh_research/1`'s own "re-fetch on every signal" status) and by
  # the `:vassals_changed`/`:new_vassal`/`:vassalized` broadcasts.
  defp refresh_vassalage(socket) do
    %{world: world, user: user} = socket.assigns
    assign(socket, vassals: Game.vassals(world, user), vassal_status: Game.vassal_status(world, user))
  end

  defp parse_agenda("restore"), do: :restore
  defp parse_agenda("usurp"), do: :usurp
  defp parse_agenda("kingmaker"), do: :kingmaker
  defp parse_agenda("merchant_prince"), do: :merchant_prince
  defp parse_agenda(_other), do: :invalid

  # `"50"` (a 0-100 percentage string, the tribute-rate control's own
  # scale) -> `0.5` (the `Vassalage.tribute_rate` fraction).
  defp parse_percent(percent) when is_binary(percent) do
    case Float.parse(percent) do
      {value, _rest} -> value / 100
      :error -> 0.0
    end
  end

  defp parse_percent(percent) when is_number(percent), do: percent / 100

  # `"0.5"` (the pledged-share control's own scale, already a fraction)
  # -> `0.5`.
  defp parse_fraction(fraction) when is_binary(fraction) do
    case Float.parse(fraction) do
      {value, _rest} -> value
      :error -> 0.0
    end
  end

  defp parse_fraction(fraction) when is_number(fraction), do: fraction

  defp tribute_rate_label(rate), do: "#{round(rate * 100)}%"

  defp oath_agenda_options do
    [
      {"restore", "Restore — reclaim your fallen realm"},
      {"usurp", "Usurp — seize your lord's own throne"},
      {"kingmaker", "Kingmaker — decide who rules"},
      {"merchant_prince", "Merchant Prince — build wealth beyond war"}
    ]
  end

  # -------------------------------------------------------------------
  # City loop helpers
  # -------------------------------------------------------------------

  # Which improvement kinds a worker could start on the tile it's
  # standing on right now — same terrain gate `WorldServer` enforces
  # (`Regions.tile_class/2` == :land, then `Improvement.allowed?/2`),
  # computed here purely so `UnitPanel` only ever offers legal actions
  # (story 882, criterion 7482: Farm is never offered on hills/forest).
  # The dig under the selected worker's feet, if one is in progress —
  # the unit panel shows it as live progress (issue b5cc4ae9: silent
  # success on Build read as a dead button).
  defp worker_current_dig(improvements, %{type: :worker, tile_id: tile_id}),
    do: Enum.find(improvements, &(&1.tile_id == tile_id and &1.status == :building))

  defp worker_current_dig(_improvements, _unit), do: nil

  defp worker_allowed_improvements(_world, nil, _player_research), do: []

  defp worker_allowed_improvements(_world, %{type: type}, _player_research) when type != :worker,
    do: []

  defp worker_allowed_improvements(world, %{tile_id: tile_id}, player_research) do
    if Regions.tile_class(world, tile_id) == :land do
      terrain = Regions.terrain(world, tile_id)
      terrain_kinds = Enum.filter([:farm, :mine, :road], &Improvement.allowed?(&1, terrain))

      if pasture_offered?(world, tile_id, player_research) do
        terrain_kinds ++ [:pasture]
      else
        terrain_kinds
      end
    else
      []
    end
  end

  # Pasture (story 905, criterion 7648) only ever renders once the tile
  # carries an animal resource AND the selecting player has researched
  # Animal Husbandry — mirrors the terrain gate above, just sourced from
  # the resource layer + research instead of `Improvement.allowed?/2`.
  defp pasture_offered?(world, tile_id, player_research) do
    Improvement.resource_allowed?(Resources.at(world, tile_id)) and
      pasture_enabled?(player_research)
  end

  defp pasture_enabled?(nil), do: false
  defp pasture_enabled?(player_research), do: Research.pasture_enabled?(player_research)

  # Territory tiles `CityPanel` may offer a "Work" action for: not the
  # always-free center, not already worked, and workable terrain — the
  # same gate `WorldServer.validate_assign/3` enforces. `CityPanel` has
  # no world/terrain access of its own (purely presentational), so this
  # is computed here whenever the selected city changes.
  defp assignable_tiles(_world, nil), do: []

  defp assignable_tiles(world, city) do
    worked = MapSet.new(city.worked_tiles)

    city.territory
    |> Enum.reject(&(&1 == city.tile_id or MapSet.member?(worked, &1)))
    |> Enum.filter(&Yields.workable?(Regions.terrain(world, &1)))
  end

  defp parse_id(nil), do: nil
  defp parse_id(""), do: nil
  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  defp city_error_message(:not_owner), do: "You don't control that city."
  defp city_error_message(:not_settler), do: "Only a settler can found a city."
  defp city_error_message(:invalid_terrain), do: "A city can't be founded there."
  defp city_error_message(:too_close), do: "Too close to an existing city."
  defp city_error_message(:invalid_item), do: "That can't be queued."
  defp city_error_message(:size_one), do: "This city needs a second citizen first."
  defp city_error_message(:not_found), do: "That item is no longer queued."
  defp city_error_message(:invalid_name), do: "Enter a name for the city."
  defp city_error_message(:not_worked), do: "That tile isn't currently worked."
  defp city_error_message(:invalid_tile), do: "The city center can't be reassigned."
  defp city_error_message(:not_territory), do: "That tile isn't part of the city."
  defp city_error_message(:already_worked), do: "That tile already has a citizen."

  defp city_error_message(:size_exceeded),
    do: "This city has no idle citizen — unassign a worked tile first."

  defp city_error_message(_other), do: "That action can't be completed."

  defp improvement_error_message(:not_owner), do: "You don't control that unit."
  defp improvement_error_message(:not_worker), do: "Only a worker can build improvements."

  defp improvement_error_message(:invalid_improvement),
    do: "That improvement isn't allowed there."

  defp improvement_error_message(:invalid_terrain),
    do: "That terrain won't support that improvement."

  defp improvement_error_message(:occupied_improvement),
    do: "This tile already has a completed improvement."

  defp improvement_error_message(:no_active_build),
    do: "There's no build in progress here to cancel."

  defp improvement_error_message(_other), do: "That improvement can't be started."

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-64px)]">
      <Layouts.flash_group flash={@flash} />

      <div class="flex items-center gap-3 px-4 py-2 bg-base-200 border-b border-base-300 flex-wrap">
        <.live_component
          module={BrokenOathsWeb.GameLive.TurnBar}
          id="turn-bar"
          turn={@turn}
          turn_ends_at={@turn_ends_at}
        />

        <span class="badge badge-neutral gap-1" data-test="player-gold">
          <.icon name="hero-circle-stack" class="w-3 h-3" /> {@gold}
        </span>

        <%!-- Story 907: the lord's own Vassals list — only mounted while
             non-empty (criterion 7667's own "no vassals-list at all"
             anchor). --%>
        <.vassals_panel :if={@vassals != []} vassals={@vassals} />

        <%!-- Story 907/908: a subjugated player's own oath — sworn-to
             badge, the rate they feel, and their own latest levy status. --%>
        <div :if={@vassal_status} class="flex items-center gap-1">
          <span class="badge badge-secondary gap-1" data-test="vassal-status">
            Sworn to {@vassal_status.lord_email}
          </span>
          <span class="badge badge-outline" data-test="my-tribute-rate">
            {tribute_rate_label(@vassal_status.tribute_rate)}
          </span>
          <span :if={@vassal_status.levy_status} class="badge badge-outline" data-test="levy-status">
            {@vassal_status.levy_status}
          </span>
        </div>

        <.live_component
          module={BrokenOathsWeb.GameLive.AgePanel}
          id="age-panel"
          player_research={@player_research}
        />

        <.live_component
          module={BrokenOathsWeb.GameLive.TechPanel}
          id="tech-panel"
          open?={@tech_panel_open?}
          player_research={@player_research}
          bronze_working_pending?={@bronze_working_pending?}
        />

        <%!-- QA issue 937ea82b "There is no help or wiki" — a first-pass,
             always-reachable in-game reference. --%>
        <.live_component module={BrokenOathsWeb.GameLive.HelpPanel} id="help-panel" />

        <div class="flex-1"></div>

        <button
          phx-click="abandon_world"
          class="btn btn-sm btn-error btn-outline"
          data-test="abandon-world"
        >
          Abandon World
        </button>

        <.link navigate={~p"/play"} class="btn btn-sm btn-ghost">All Worlds</.link>
      </div>

      <div :if={@confirm_abandon?} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Abandon this world?</h3>
          <p class="py-4 opacity-70">
            Your civilization will be wiped and your region freed for another player. This cannot be undone.
          </p>
          <div class="modal-action">
            <button phx-click="abandon_cancel" class="btn btn-ghost">Cancel</button>
            <button phx-click="abandon_confirm" class="btn btn-error" data-test="abandon-confirm">
              Abandon Forever
            </button>
          </div>
        </div>
      </div>

      <%!-- Story 907 — the Oath screen: raised the moment a capture
           leaves this player with zero free cities, closed the instant
           they secretly pick a Hidden Agenda (`choose_hidden_agenda`). --%>
      <div :if={@vassal_status && @vassal_status.agenda_pending?} class="modal modal-open" data-test="oath-screen">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Terms of Oath</h3>
          <p class="py-2 opacity-70">
            Your last free city has fallen. You are sworn to {@vassal_status.lord_email} — but your
            story is far from over. Choose the ambition you'll secretly pursue as a vassal:
          </p>
          <div class="flex flex-col gap-2">
            <button
              :for={{agenda, label} <- oath_agenda_options()}
              type="button"
              phx-click="choose_hidden_agenda"
              phx-value-agenda={agenda}
              data-test={"agenda-option-#{agenda}"}
              class="btn btn-outline justify-start"
            >
              {label}
            </button>
          </div>
        </div>
      </div>

      <div class="flex flex-1 min-h-0 relative">
        <div
          id="board-viewport"
          class="flex-1 overflow-hidden space-bg relative touch-none"
          phx-hook=".Board"
          data-yaw={@yaw}
          data-pitch={@pitch}
          data-scale={@scale}
        >
          <div id="board-own" phx-update="ignore" class="board-own">
            <canvas class="board-canvas" style="width:100%;height:100%;"></canvas>
          </div>

          <div class="fog-layer pointer-events-none absolute inset-0" data-test="fog-layer"></div>
          <div class="weather-layer pointer-events-none absolute inset-0" data-test="weather-layer">
          </div>
        </div>

        <%!-- Story 899/900/901: the durable Known Players roster +
             discovery toast affordance, the chat button/panel beside it,
             and the alliance button/panel beside that. `KnownPlayersPanel`
             is hidden while `ChatPanel` is open — its own contact list
             reuses the same "known-player-ID" row shape, so only one of
             the two is ever on the page at once (the same "one side panel
             at a time" rule Play already applies to unit/city selection).
             `AlliancePanel` uses its own distinct "ally-candidate-ID"/
             "alliance-ID" naming (see its own moduledoc), so it never
             needs that same exclusion — both button rows stay reachable
             together. --%>
        <div class="absolute top-4 right-4 flex flex-col gap-2 items-end">
          <.live_component
            :if={!@chat_open}
            module={BrokenOathsWeb.GameLive.KnownPlayersPanel}
            id="known-players-panel"
            known_players={@known_players}
          />

          <div class="flex gap-2">
            <.live_component
              module={BrokenOathsWeb.GameLive.ChatPanel}
              id="chat-panel"
              world={@world}
              user={@user}
              chat_target_user_id={@chat_target_user_id}
            />

            <.live_component
              module={BrokenOathsWeb.GameLive.AlliancePanel}
              id="alliance-panel"
              world={@world}
              user={@user}
              known_players={@known_players}
            />
          </div>
        </div>

        <div class="absolute top-4 left-4 flex flex-col gap-2 items-start">
          <div :if={@order_error} class="alert alert-error w-auto shadow-lg" data-test="order-error">
            <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@order_error}
          </div>

          <div
            :if={@combat_error}
            class="alert alert-error w-auto shadow-lg"
            data-test="combat-error"
          >
            <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@combat_error}
          </div>

          <div :if={@city_error} class="alert alert-error w-auto shadow-lg" data-test="city-error">
            <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@city_error}
          </div>

          <div
            :if={@improvement_error}
            class="alert alert-error w-auto shadow-lg"
            data-test="improvement-error"
          >
            <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@improvement_error}
          </div>
        </div>

        <%!-- Story 904: the Stone Age progress panel — always visible,
             unrelated to unit/city selection, same "durable, not a
             selection-triggered side panel" status `KnownPlayersPanel`
             already has (see that component's own moduledoc). --%>
        <div class="absolute bottom-4 left-4">
          <.live_component
            module={BrokenOathsWeb.GameLive.ProgressPanel}
            id="progress-panel"
            player_research={@player_research}
            cities_founded={length(@cities)}
            camps_destroyed={@player_stats.camps_destroyed}
            barbarians_killed={@player_stats.barbarians_killed}
            players_discovered={length(@known_players)}
          />
        </div>

        <%!-- QA issue e51a31be "UI issues" — the selection detail pane
             (tile/unit/city/camp): absolutely positioned so it never
             stretches to the board's full height or crowds board-viewport
             out of the flex row (the original bug — a plain flow child
             under a `relative` container with no `items-start` stretched
             to 100% height and sat directly under the top-right corner
             overlays), sized to its own content, anchored to the one
             free corner (top-right is Known Players/Chat/Alliance,
             bottom-left is Progress), and capped/scrollable so even a
             tall panel never covers the whole board. Every panel gets
             its own close (X), routed through the shared
             "clear_selection" handler. --%>
        <div
          :if={@selected_tile || @selected_unit || @selected_city || @selected_camp}
          data-test="detail-pane"
          class="absolute bottom-4 right-4 z-20 max-h-[70vh] overflow-y-auto flex flex-col gap-2"
        >
          <div
            :if={@selected_tile}
            class="card bg-base-200/95 shadow-xl w-64 relative"
            data-test="tile-panel"
          >
            <button
              type="button"
              phx-click="clear_selection"
              data-test="close-tile-panel"
              class="btn btn-ghost btn-xs btn-circle absolute top-1 right-1"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
            <div class="card-body p-4 gap-1">
              <h3 class="card-title text-sm pr-6" data-test="tile-terrain">
                {@selected_tile.terrain}
              </h3>
              <p class="text-xs opacity-80" data-test="tile-yields">
                +{@selected_tile.food} food · +{@selected_tile.production} production
              </p>
              <p :if={@selected_tile.improvement} class="text-xs" data-test="tile-improvement">
                {improvement_summary(@selected_tile.improvement)}
              </p>
              <p :if={@selected_tile.resource} class="text-xs" data-test="tile-resource">
                {resource_label(@selected_tile.resource)}
              </p>
            </div>
          </div>

          <%!-- QA issue 748348fe "barbarian camp issues" — a camp under
               siege now shows its own HP, the same "watch it drop"
               readout `city-hp` already gives a besieged city. --%>
          <div
            :if={@selected_camp}
            class="card bg-base-200/95 shadow-xl w-64 relative"
            data-test="camp-panel"
          >
            <button
              type="button"
              phx-click="clear_selection"
              data-test="close-camp-panel"
              class="btn btn-ghost btn-xs btn-circle absolute top-1 right-1"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
            <div class="card-body p-4 gap-1">
              <h3 class="card-title text-sm pr-6" data-test="camp-name">Barbarian Camp</h3>
              <span class="badge badge-error badge-outline w-fit" data-test="camp-hp">
                {@selected_camp.hp}/{Camp.max_hp()}
              </span>
            </div>
          </div>

          <.live_component
            :if={@selected_unit}
            module={BrokenOathsWeb.GameLive.UnitPanel}
            id="unit-panel"
            unit={@selected_unit}
            order={@selected_order}
            allowed_improvements={@allowed_improvements}
            current_dig={@current_dig}
          />

          <.live_component
            :if={@selected_city}
            module={BrokenOathsWeb.GameLive.CityPanel}
            id="city-panel"
            city={@selected_city}
            assignable_tiles={@assignable_tiles}
            player_research={@player_research}
          />
        </div>
      </div>

      <%!-- Canvas-only board: no tile DOM. Camera (drag rotate + wheel zoom)
           lives entirely client-side since fog is unit-position-derived, not
           camera-derived — the server never needs to know the current view.
           A left click on a unit selects it; a right click queues a move
           toward the clicked point on the sphere — resolved to a tile
           server-side, so targets under the fog of war work too. --%>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Board">
        export default {
          mounted() {
            this.canvas = this.el.querySelector(".board-canvas")
            this.ctx = this.canvas.getContext("2d")

            const d = this.el.dataset
            this.yaw = parseFloat(d.yaw) || 0
            this.pitch = parseFloat(d.pitch) || 0
            this.scale = parseFloat(d.scale) || 700
            this.maxPitch = 1.50

            this.tiles = []
            this.tileById = new Map()
            this.units = []
            this.cities = []
            this.camps = []
            this.improvements = []
            this.citySelection = null
            this.resources = []
            this.visibleSet = new Set()
            this.selectedId = null
            this.path = null
            this.anims = new Map()
            this.raf = null
            this.arc = 0.02

            // Billboard sprites + ground textures via the shared render
            // core (assets/js/globe_render.js — ADR game-art-pipeline).
            // Anything not yet loaded falls back to programmer art.
            const GR = window.GlobeRender
            this.sprites = GR.loadSprites(() => this.draw())
            this.terrainTex = GR.loadTerrainTextures(() => this.draw())
            this.patterns = GR.patternPool(this.terrainTex)
            this.CLOUD = GR.cloudFlat()

            const measure = () => {
              const r = this.el.getBoundingClientRect()
              this.cx = r.width / 2
              this.cy = r.height / 2
              const dpr = Math.min(window.devicePixelRatio || 1, 2)
              this.canvas.width = Math.max(Math.round(r.width * dpr), 1)
              this.canvas.height = Math.max(Math.round(r.height * dpr), 1)
              this.dpr = dpr
              this.draw()
            }
            measure()
            this.ro = new ResizeObserver(measure)
            this.ro.observe(this.el)

            this.airspace = {}
            this.handleEvent("globe3d:airspace", ({levels, arc}) => {
              this.airspace = levels
              if (arc) this.arc = arc
              this.draw()
            })
            this.handleEvent("game:window", ({tiles}) => {
              this.tiles = tiles
              this.tileById = new Map(tiles.map((row) => [row[0], row]))
              this.draw()
            })
            this.handleEvent("game:visibility", ({visible}) => { this.visibleSet = new Set(visible); this.draw() })
            this.handleEvent("game:units", ({units}) => {
              // A unit whose tile changed slides there instead of teleporting.
              const prev = new Map(this.units.map((u) => [u.id, u.tile_id]))
              const now = performance.now()
              for (const u of units) {
                const was = prev.get(u.id)
                if (was != null && was !== u.tile_id) {
                  const from = this.unitPos({id: u.id, tile_id: was}, now)
                  const to = this.center(u.tile_id)
                  if (from && to) this.anims.set(u.id, {from, to, start: now})
                }
              }
              this.units = units
              this.ensureLoop()
              this.draw()
            })
            this.handleEvent("game:cities", ({cities}) => { this.cities = cities; this.draw() })
            this.handleEvent("game:camps", ({camps}) => { this.camps = camps; this.draw() })
            this.handleEvent("game:city_selection", ({territory, worked_tiles}) => {
              this.citySelection = (territory && territory.length)
                ? {territory, workedTiles: worked_tiles || []}
                : null
              this.draw()
            })
            this.handleEvent("game:combat", ({damage_dealt, damage_taken}) => {
              this.combatFlash = {dealt: damage_dealt, taken: damage_taken, until: performance.now() + 2500}
              this.ensureLoop()
              this.draw()
            })
            this.handleEvent("game:improvements", ({improvements}) => { this.improvements = improvements; this.draw() })
            this.handleEvent("game:resources", ({resources}) => { this.resources = resources; this.draw() })
            this.handleEvent("game:selected", ({unit_id}) => { this.selectedId = unit_id; this.path = null; this.draw() })
            this.handleEvent("game:path", ({unit_id, tiles}) => {
              if (unit_id === this.selectedId) this.path = tiles
              this.draw()
            })

            // Transient player-scoped notifications (story 895 alert,
            // 896 lineage, 899 discovery) arrive as one-shot pushes with
            // no socket assign — render each as an auto-dismissing toast.
            const showToast = (message) => {
              if (!message) return
              let wrap = document.getElementById("game-toasts")
              if (!wrap) {
                wrap = document.createElement("div")
                wrap.id = "game-toasts"
                wrap.className = "toast toast-top toast-center z-50"
                document.body.appendChild(wrap)
              }
              const el = document.createElement("div")
              el.className = "alert alert-info shadow-lg"
              el.setAttribute("data-test", "game-toast")
              el.textContent = message
              wrap.appendChild(el)
              setTimeout(() => el.remove(), 6000)
            }
            this.handleEvent("game:discovery", ({message}) => showToast(message))
            this.handleEvent("game:alert", ({message}) => showToast(message))
            this.handleEvent("game:lineage", ({message}) => showToast(message))
            this.handleEvent("game:age", ({message}) => showToast(message))

            // Unified pointer input for mouse, pen and touch. One active
            // pointer pans (drag); two active pointers pinch-zoom and
            // pan by their midpoint. `touch-action: none` on the element
            // keeps the browser from stealing the gesture for page scroll
            // or its own pinch-zoom. Wheel (below) stays for desktop.
            this.pointers = new Map()
            this.moved = false
            this.button = 0

            const pinchDist = () => {
              const [a, b] = [...this.pointers.values()]
              return Math.hypot(a.x - b.x, a.y - b.y)
            }
            const pinchMid = () => {
              const [a, b] = [...this.pointers.values()]
              return {x: (a.x + b.x) / 2, y: (a.y + b.y) / 2}
            }
            const panBy = (dx, dy) => {
              this.yaw -= dx / this.scale / Math.max(Math.cos(this.pitch), 0.25)
              this.pitch = Math.max(-this.maxPitch, Math.min(this.maxPitch, this.pitch + dy / this.scale))
            }

            this.el.addEventListener("pointerdown", (e) => {
              // Synthetic/edge pointer ids (e.g. QA-script-injected
              // events) can make the browser throw NotFoundError here —
              // never let that abort the rest of pointer handling below.
              try {
                this.el.setPointerCapture(e.pointerId)
              } catch (_) {}
              this.pointers.set(e.pointerId, {x: e.clientX, y: e.clientY})
              this.button = e.button
              this.moved = false
              clearTimeout(this.lpTimer)
              if (this.pointers.size === 2) {
                this.pinchLast = pinchDist()
                this.midLast = pinchMid()
              } else {
                this.last = {x: e.clientX, y: e.clientY}
                this.longPressed = false
                // Touch has no right-click: a long press (held in place)
                // queues a move order — the touch equivalent of the RTS
                // right-click. Desktop keeps right-click for this.
                if (e.pointerType === "touch") {
                  const at = {clientX: e.clientX, clientY: e.clientY}
                  this.lpTimer = setTimeout(() => {
                    if (this.pointers.size === 1 && !this.moved) {
                      this.longPressed = true
                      if (navigator.vibrate) navigator.vibrate(30)
                      this.orderMove(at)
                    }
                  }, 500)
                }
              }
            })

            // Right-click is a game action (queue move), not a menu
            this.el.addEventListener("contextmenu", (e) => e.preventDefault())

            this.el.addEventListener("pointermove", (e) => {
              if (!this.pointers.has(e.pointerId)) return
              this.pointers.set(e.pointerId, {x: e.clientX, y: e.clientY})

              if (this.pointers.size >= 2) {
                this.moved = true
                clearTimeout(this.lpTimer)
                const dist = pinchDist()
                if (this.pinchLast > 0) {
                  this.scale = Math.max(200, Math.min(this.scale * (dist / this.pinchLast), 4000))
                }
                this.pinchLast = dist
                const mid = pinchMid()
                if (this.midLast) panBy(mid.x - this.midLast.x, mid.y - this.midLast.y)
                this.midLast = mid
                this.draw()
                return
              }

              const dx = e.clientX - this.last.x
              const dy = e.clientY - this.last.y
              if (!this.moved && Math.abs(dx) + Math.abs(dy) < 4) return
              this.moved = true
              clearTimeout(this.lpTimer)
              this.last = {x: e.clientX, y: e.clientY}
              panBy(dx, dy)
              this.draw()
            })

            const removePointer = (e) => {
              clearTimeout(this.lpTimer)
              const had = this.pointers.delete(e.pointerId)
              if (this.pointers.size < 2) {
                this.pinchLast = 0
                this.midLast = null
              }
              if (this.pointers.size === 1) {
                const [p] = [...this.pointers.values()]
                this.last = {x: p.x, y: p.y}
              }
              return had
            }

            this.el.addEventListener("pointerup", (e) => {
              const had = removePointer(e)
              // A tap (no drag, last finger up, not already a long-press)
              // is a board action
              if (had && this.pointers.size === 0 && !this.moved && !this.longPressed) {
                if (this.button === 2) this.orderMove(e)
                else this.click(e)
              }
            })
            this.el.addEventListener("pointercancel", removePointer)

            this.el.addEventListener("wheel", (e) => {
              e.preventDefault()
              this.scale = Math.max(200, Math.min(this.scale * (e.deltaY < 0 ? 1.1 : 0.9), 4000))
              this.draw()
            }, {passive: false})
          },

          view() {
            return {yaw: this.yaw, pitch: this.pitch, scale: this.scale, cx: this.cx, cy: this.cy}
          },

          unproject(sx, sy) {
            return window.GlobeRender.unproject(this.view(), sx, sy)
          },

          project(x, y, z) {
            const GR = window.GlobeRender
            return GR.project(GR.rot(this.view()), x, y, z)
          },

          // Nearest tile to a screen point, by exact tile geometry —
          // correct at any zoom (no fuzzy capture radius).
          hitTile(e) {
            const r = this.el.getBoundingClientRect()
            const p = this.unproject(e.clientX - r.left, e.clientY - r.top)
            if (!p || this.tiles.length === 0) return null

            let nearestTile = null, bestTileDot = -Infinity
            for (const row of this.tiles) {
              const dot = row[4] * p.x + row[5] * p.y + row[6] * p.z
              if (dot > bestTileDot) { bestTileDot = dot; nearestTile = row[0] }
            }

            return nearestTile
          },

          // Left click: select the unit standing on the clicked tile: if
          // none is there but one of my own cities is, select that
          // instead (mutually exclusive side panels — see Play's
          // moduledoc). A click on empty ground selects nothing.
          click(e) {
            const tile = this.hitTile(e)
            if (tile == null) return

            const unit = this.units.find((u) => u.tile_id === tile)
            if (unit) { this.pushEvent("select_unit", {unit_id: unit.id}); return }

            const city = this.cities.find((c) => c.tile_id === tile)
            if (city) { this.pushEvent("select_city", {city_id: city.id}); return }

            // QA issue 748348fe — a barbarian camp is selectable too,
            // the same left-click convention as a unit/city, so a
            // besieging player can watch its HP drop.
            const camp = this.camps.find((c) => c.tile_id === tile)
            if (camp) { this.pushEvent("select_camp", {camp_id: camp.id}); return }

            // Open ground: show the tile's own info (terrain, yields,
            // improvement) — but only for tiles the player knows, which
            // is all the client ever has.
            this.pushEvent("select_tile", {tile_id: tile})
          },

          // Right click: queue the selected unit's move toward the clicked
          // point on the globe. The point (not a tile id) goes up because
          // the client's tile window is fog-filtered — the server resolves
          // which tile was aimed at, so orders into the shroud work.
          orderMove(e) {
            if (this.selectedId == null) return

            // A right click on an adjacent barbarian or camp is an
            // attack order, not a move — the RTS convention (story
            // 891/894). Anything else falls through to movement.
            const tile = this.hitTile(e)
            if (tile != null) {
              const enemy = this.units.find((u) => u.tile_id === tile && u.type === "barbarian_warrior")
              if (enemy) { this.pushEvent("attack", {unit_id: this.selectedId, target_unit_id: enemy.id}); return }
              const camp = this.camps.find((c) => c.tile_id === tile)
              if (camp) { this.pushEvent("attack", {unit_id: this.selectedId, target_camp_id: camp.id}); return }
            }

            const r = this.el.getBoundingClientRect()
            const p = this.unproject(e.clientX - r.left, e.clientY - r.top)
            if (!p) return

            this.pushEvent("queue_move", {unit_id: this.selectedId, to_point: [p.x, p.y, p.z]})
          },

          center(tileId) {
            const row = this.tileById.get(tileId)
            return row ? [row[4], row[5], row[6]] : null
          },

          spriteFor(key) {
            return window.GlobeRender.ready(key && this.sprites[key])
          },

          // Fallback dot colors (story 905) — food resources warm, the
          // one production resource (Stone) cool, so the two families
          // read apart even before real icon art exists.
          resourceColor(kind) {
            const colors = {cattle: "#c2703d", sheep: "#e8dcc8", wheat: "#e8b923", stone: "#8a8f98"}
            return colors[kind] || "#eab308"
          },

          // Where a unit currently renders: mid-slide if animating,
          // otherwise its tile center.
          unitPos(u, now) {
            const a = this.anims.get(u.id)
            if (!a) return this.center(u.tile_id)
            const t = Math.min(1, (now - a.start) / 450)
            const ease = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2
            return this.slerp(a.from, a.to, ease)
          },

          slerp(a, b, t) {
            let dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
            dot = Math.min(1, Math.max(-1, dot))
            const th = Math.acos(dot)
            if (th < 1e-4) return b
            const s = Math.sin(th)
            const wa = Math.sin((1 - t) * th) / s
            const wb = Math.sin(t * th) / s
            return [a[0] * wa + b[0] * wb, a[1] * wa + b[1] * wb, a[2] * wa + b[2] * wb]
          },

          // Animation loop — runs only while a slide is in flight or a
          // unit with a pending path needs its pulse.
          ensureLoop() {
            if (this.raf) return
            const step = () => {
              this.raf = null
              const now = performance.now()
              for (const [id, a] of this.anims) {
                if (now - a.start > 450) this.anims.delete(id)
              }
              this.draw()
              const pulsing = this.units.some((u) => u.order && u.order.status === "pending")
              const flashing = this.combatFlash && now < this.combatFlash.until
              if (this.anims.size || pulsing || flashing) this.raf = requestAnimationFrame(step)
            }
            this.raf = requestAnimationFrame(step)
          },

          draw() {
            const ctx = this.ctx
            if (!ctx) return
            const GR = window.GlobeRender
            const dpr = this.dpr || 1
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
            ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)

            // Fog of war: the unexplored planet is a flat, opaque,
            // colorless cloud shroud — the "cloud-wrapped" globe. Known
            // tiles paint over it; everything else stays under cloud.
            ctx.beginPath()
            ctx.arc(this.cx, this.cy, this.scale, 0, 2 * Math.PI)
            ctx.fillStyle = "#a8acb5"
            ctx.fill()

            const R = GR.rot(this.view())
            const order = this.tiles
              .map((row) => {
                const c = GR.project(R, row[4], row[5], row[6])
                return {row, depth: c.depth, cx: c.px, cy: c.py}
              })
              .filter(({depth}) => depth > 0.02)
              .sort((a, b) => a.depth - b.depth)

            for (const {row, cx, cy} of order) {
              const [id, color] = row
              ctx.beginPath()
              GR.tracePolygon(ctx, R, row, 7)
              ctx.fillStyle = this.patterns.for(ctx, row[3], this.scale, cx, cy) || color
              ctx.fill()

              // Explored-but-out-of-vision: remembered terrain under a
              // thin wash of the fog tone (distinct from full shroud)
              if (!this.visibleSet.has(id)) {
                ctx.fillStyle = "rgba(168,172,181,0.45)"
                ctx.fill()
              }
            }

            // Terrain decor billboards (mountains, hills, tree cover) at
            // projected tile centers, back-to-front, dimmed on remembered
            // tiles. Skipped entirely below readability size.
            ctx.imageSmoothingEnabled = false
            const decorSize = Math.min(Math.max(this.scale * this.arc * 1.7, 10), 72)
            if (decorSize >= 10) {
              for (const {row, cx, cy} of order) {
                const img = this.spriteFor(row[2])
                if (!img) continue
                ctx.globalAlpha = this.visibleSet.has(row[0]) ? 1 : 0.55
                GR.drawBillboard(ctx, img, cx, cy, decorSize)
              }
              ctx.globalAlpha = 1
            }

            // Bonus-resource markers (story 905): small, distinct dots
            // so a resource tile reads as "special" at a glance from
            // the very first look (criterion 7649 — no reveal tech, no
            // city/improvement needed). Falls back to a flat colored
            // dot when the real icon art isn't loaded yet — same
            // "never block on an asset request" rule the city
            // billboard's own fallback already follows below.
            const resourceSize = Math.min(Math.max(this.scale * this.arc * 1.3, 8), 56)
            if (resourceSize >= 8) {
              for (const res of this.resources) {
                const pos = this.center(res.tile_id)
                if (!pos) continue
                const {px, py, depth} = this.project(pos[0], pos[1], pos[2])
                if (depth < 0.02) continue
                ctx.globalAlpha = this.visibleSet.has(res.tile_id) ? 1 : 0.55
                const img = this.spriteFor(res.kind)
                if (img) {
                  GR.drawBillboard(ctx, img, px, py, resourceSize)
                } else {
                  ctx.beginPath()
                  ctx.arc(px, py, resourceSize * 0.22, 0, 2 * Math.PI)
                  ctx.fillStyle = this.resourceColor(res.kind)
                  ctx.fill()
                  ctx.lineWidth = 1.5
                  ctx.strokeStyle = "#1a1a1a"
                  ctx.stroke()
                }
                ctx.globalAlpha = 1
              }
            }

            // Improvement billboards (farms, mines): built ON the
            // terrain like decor, below cities/units. Pillaged ones
            // render half-faded — visibly wrecked, visibly repairable.
            const impSize = Math.min(Math.max(this.scale * this.arc * 1.6, 10), 68)
            if (impSize >= 10) {
              for (const imp of this.improvements) {
                if (imp.status === "building") continue
                const pos = this.center(imp.tile_id)
                if (!pos) continue
                const {px, py, depth} = this.project(pos[0], pos[1], pos[2])
                if (depth < 0.02) continue
                const img = this.spriteFor(imp.kind)
                if (!img) continue
                ctx.globalAlpha = imp.status === "pillaged" ? 0.4 : (this.visibleSet.has(imp.tile_id) ? 1 : 0.55)
                GR.drawBillboard(ctx, img, px, py, impSize)
                ctx.globalAlpha = 1
              }
            }

            // Barbarian camp billboards — hostile landmarks, same layer
            // rules as improvements (under cities and units).
            const campSize = Math.min(Math.max(this.scale * this.arc * 1.9, 12), 76)
            if (campSize >= 10) {
              for (const c of this.camps) {
                const pos = this.center(c.tile_id)
                if (!pos) continue
                const {px, py, depth} = this.project(pos[0], pos[1], pos[2])
                if (depth < 0.02) continue
                const img = this.spriteFor("camp")
                if (!img) continue
                ctx.globalAlpha = this.visibleSet.has(c.tile_id) ? 1 : 0.55
                GR.drawBillboard(ctx, img, px, py, campSize)
                ctx.globalAlpha = 1
              }
            }

            // City billboards: player-owned settlements, drawn after
            // decor (so they read as built ON the terrain) but before
            // weather (so cloud cover still darkens the skyline) and
            // before units (so a garrisoned unit renders on top of its
            // city, not hidden beneath it). Deliberately larger than a
            // decor sprite — a city is the main thing on its tile.
            const citySize = Math.min(Math.max(this.scale * this.arc * 2.2, 16), 88)
            if (citySize >= 10) {
              for (const c of this.cities) {
                const pos = this.center(c.tile_id)
                if (!pos) continue
                const {px, py, depth} = this.project(pos[0], pos[1], pos[2])
                if (depth < 0.02) continue

                const img = this.spriteFor("city")
                if (img) {
                  GR.drawBillboard(ctx, img, px, py, citySize)
                } else {
                  // Fallback programmer art — same "never block on an
                  // asset request" rule the unit/decor layers follow.
                  ctx.beginPath()
                  ctx.arc(px, py, citySize * 0.18, 0, 2 * Math.PI)
                  ctx.fillStyle = "#c9a227"
                  ctx.fill()
                  ctx.lineWidth = 2
                  ctx.strokeStyle = "#1a1a1a"
                  ctx.stroke()
                }
              }
            }

            // Story 759d02c8/0b8a75e4 (v0.2.1 playtest) — the selected
            // city's own territory border and worked-tile highlight,
            // Civ-style. Scoped to ONLY the selected city's own tiles
            // (never every city on the board) for performance. The
            // border is the set of polygon edges that belong to exactly
            // ONE territory tile — an edge shared by two territory
            // tiles is an interior seam, not a border — computed once
            // per draw by the shared render core's `computeBorderEdges`.
            // Tile-id labels are the SAME "Tile N" number the City
            // panel's worked/assignable rows already show (issue
            // 0b8a75e4: a raw tile id had nothing to visually anchor
            // it to), so a player can match a panel row to its board
            // location at a glance.
            if (this.citySelection) {
              const territorySet = new Set(this.citySelection.territory)
              const workedSet = new Set(this.citySelection.workedTiles)
              const territoryRows = order.filter(({row}) => territorySet.has(row[0]))

              for (const {row} of territoryRows) {
                if (!workedSet.has(row[0])) continue
                ctx.beginPath()
                GR.tracePolygon(ctx, R, row, 7)
                ctx.fillStyle = "rgba(250, 204, 21, 0.35)"
                ctx.fill()
              }

              const edges = GR.computeBorderEdges(territoryRows.map(({row}) => row))
              ctx.strokeStyle = "#ffffff"
              ctx.lineWidth = 2
              for (const [a, b] of edges) {
                const pa = this.project(a[0], a[1], a[2])
                const pb = this.project(b[0], b[1], b[2])
                if (pa.depth < 0.02 || pb.depth < 0.02) continue
                ctx.beginPath()
                ctx.moveTo(pa.px, pa.py)
                ctx.lineTo(pb.px, pb.py)
                ctx.stroke()
              }

              ctx.font = "bold 11px ui-monospace, monospace"
              ctx.textAlign = "center"
              ctx.fillStyle = "#ffffff"
              for (const {row, cx, cy} of territoryRows) {
                ctx.fillText(String(row[0]), cx, cy)
              }
              ctx.textAlign = "start"
            }

            // Weather: translucent cloud hexes one shell above known
            // terrain (levels from the airspace push; palette from the
            // shared render core). Deliberately translucent + tinted so
            // it never reads as the flat opaque fog shroud.
            for (const {row} of order) {
              const lvl = this.airspace[row[0]]
              if (!lvl) continue
              ctx.beginPath()
              GR.tracePolygon(ctx, R, row, 7, GR.CLOUD_ALT)
              ctx.fillStyle = this.CLOUD[lvl]
              ctx.fill()
            }

            const now = performance.now()
            const unitSize = Math.min(Math.max(this.scale * this.arc * 1.5, 14), 64)
            for (const u of this.units) {
              const pos = this.unitPos(u, now)
              if (!pos) continue
              const {px, py, depth} = this.project(pos[0], pos[1], pos[2])
              if (depth < 0.02) continue
              const barbarian = u.type === "barbarian_warrior"
              // QA issue 9482a674 — bronze_spearman gets its own bronze
              // fallback color (matching its sprite's palette) instead
              // of silently inheriting the generic blue dot every other
              // unit type without a special case used to fall back to.
              const color = barbarian
                ? "#b91c1c"
                : u.type === "lord"
                  ? "#f5c542"
                  : u.type === "bronze_spearman"
                    ? "#b8732d"
                    : "#42a5f5"
              const img = this.spriteFor(barbarian ? "barbarian" : u.type)
              const ringR = img ? unitSize * 0.45 : 8

              // A unit with a pending path pulses — the "I'm on the move"
              // signal, visible without selecting it.
              if (u.order && u.order.status === "pending") {
                const ph = (now % 1200) / 1200
                ctx.beginPath()
                ctx.arc(px, py, ringR + ph * 8, 0, 2 * Math.PI)
                ctx.strokeStyle = color
                ctx.globalAlpha = 0.7 * (1 - ph)
                ctx.lineWidth = 2
                ctx.stroke()
                ctx.globalAlpha = 1
              }

              if (img) {
                // Ground ellipse marks selection under the sprite's feet.
                if (u.id === this.selectedId) {
                  ctx.beginPath()
                  ctx.ellipse(px, py + unitSize * 0.28, unitSize * 0.4, unitSize * 0.16, 0, 0, 2 * Math.PI)
                  ctx.strokeStyle = "#ffffff"
                  ctx.lineWidth = 2
                  ctx.stroke()
                }
                ctx.drawImage(img, px - unitSize / 2, py - unitSize * 0.68, unitSize, unitSize)
              } else {
                // Fallback programmer art — the board never depends on an
                // asset request to be playable (ADR game-art-pipeline).
                ctx.beginPath()
                ctx.arc(px, py, u.id === this.selectedId ? 7 : 5, 0, 2 * Math.PI)
                ctx.fillStyle = color
                ctx.fill()
                ctx.lineWidth = 1.5
                ctx.strokeStyle = "#1a1a1a"
                ctx.stroke()
              }
            }

            if (this.path && this.path.length) {
              ctx.beginPath()
              // Path steps under fog have no client geometry — the line
              // simply bridges between the tiles the player knows.
              this.path.forEach((tileId) => {
                const c = this.center(tileId)
                if (!c) return
                const {px, py} = this.project(c[0], c[1], c[2])
                ctx.lineTo(px, py)
              })
              ctx.strokeStyle = "#ffffff"
              ctx.lineWidth = 2
              ctx.setLineDash([4, 4])
              ctx.stroke()
              ctx.setLineDash([])
            }

            // Battle report flash: the last combat's damage exchange,
            // fading out top-center for a couple of seconds.
            if (this.combatFlash) {
              const t = performance.now()
              if (t < this.combatFlash.until) {
                ctx.globalAlpha = Math.min(1, (this.combatFlash.until - t) / 800)
                ctx.font = "bold 15px ui-monospace, monospace"
                ctx.textAlign = "center"
                ctx.fillStyle = "#fca5a5"
                ctx.fillText(
                  `⚔ dealt ${this.combatFlash.dealt} · took ${this.combatFlash.taken}`,
                  this.cx, 34
                )
                ctx.globalAlpha = 1
                ctx.textAlign = "start"
              } else {
                this.combatFlash = null
              }
            }
          },

          destroyed() {
            if (this.ro) this.ro.disconnect()
            if (this.raf) cancelAnimationFrame(this.raf)
          }
        }
      </script>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Vassalage / Tribute components (stories 906/907/908)
  # -------------------------------------------------------------------

  # The lord's own "Vassals" list — a dropdown so it never crowds the
  # top bar; only mounted at all while `@vassals` is non-empty
  # (`BrokenOathsSpex.Story907.Criterion7667Spex`'s own anchor: no
  # `vassals-list` element exists at all for a lord with zero vassals).
  attr :vassals, :list, required: true

  defp vassals_panel(assigns) do
    ~H"""
    <div data-test="vassals-list" class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-sm btn-outline gap-1">
        <.icon name="hero-users" class="w-3 h-3" /> Vassals ({length(@vassals)})
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-10 menu p-3 shadow bg-base-100 rounded-box w-80 gap-3"
      >
        <.vassal_row :for={vassal <- @vassals} vassal={vassal} />
      </div>
    </div>
    """
  end

  attr :vassal, :map, required: true

  defp vassal_row(assigns) do
    ~H"""
    <div
      data-test={"vassal-row-#{@vassal.vassal_user_id}"}
      class="flex flex-col gap-1 border-b border-base-300 pb-2 last:border-b-0"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm">{@vassal.email}</span>
        <span class="badge badge-outline badge-sm" data-test="vassal-tribute-rate">
          {tribute_rate_label(@vassal.tribute_rate)}
        </span>
      </div>

      <div class="flex items-center justify-between text-xs opacity-70">
        <span>Oath Strain <span data-test="vassal-oath-strain">{@vassal.oath_strain}</span></span>
        <span :if={@vassal.levy_status} data-test="levy-status">{@vassal.levy_status}</span>
      </div>

      <form phx-submit="set_tribute_rate" class="flex items-center gap-1">
        <input type="hidden" name="vassal_user_id" value={@vassal.vassal_user_id} />
        <input
          type="number"
          name="rate"
          min="0"
          max="100"
          value={round(@vassal.tribute_rate * 100)}
          class="input input-xs input-bordered w-16"
        />
        <span class="text-xs">%</span>
        <button type="submit" class="btn btn-xs">Set Rate</button>
      </form>
    </div>
    """
  end
end
