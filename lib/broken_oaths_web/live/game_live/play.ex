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
    * `game:cities`     — `%{cities: [%{id:, name:, tile_id:, size:, hostile:}]}`,
                           the player's own cities (never fog-filtered — a
                           city is only ever seen by its owner here, `hostile:
                           false`) PLUS, once `Game.feudal_enabled?/0` (QA
                           issue 56ee521a), fog-filtered ENEMY cities the
                           player currently knows (`hostile: true`, the same
                           "own region OR explored" rule `game:camps` already
                           uses — see `Game.enemy_cities_visible_to/2`) —
                           powers the right-click ATTACK target on a hostile
                           city (mirroring a barbarian/camp) and the
                           adjacent-unit attack affordance in `UnitPanel`.
                           Every hostile entry also carries `hp:`/`broken:`
                           (QA issue 7f91cff2, `Siege.broken?/1`) — once a
                           hostile city hits 0 HP, the `.Board` hook's
                           `orderMove/1` routes a right-click at its tile to
                           `queue_move` (walk in and occupy — Civ-style, no
                           range-flip) instead of another `attack`, and
                           `UnitPanel`'s own button swaps from "Attack" to
                           "Move In" the same way
    * `game:resources`  — `%{resources: [%{tile_id:, kind:}]}` (story 905),
                           bonus-resource billboards for every currently
                           known (visible ∪ explored) tile — resources are
                           visible unconditionally (no reveal tech), the same
                           fog rule as terrain itself, so this rides the same
                           `known` set `game:window` already computes rather
                           than a separate fog-gated `Game` read. Copper
                           (story 911, the map's first STRATEGIC resource)
                           is the one exception: it stays out of this list
                           until the viewing player has completed Bronze
                           Working (`visible_resource/3`), mirroring Civ 6's
                           own "Bronze Working reveals Iron" convention
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
                           (`Diplomacy.Discovery`) finds a new pair — player-scoped,
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

  ## Siege / Garrison-fate / Levy UI (QA batch, story 906/908 gaps)

  Three real player affordances that used to exist only as bare
  `handle_event/3` clauses reachable through `attempt_event/3` in specs
  (never a real click), now surfaced for real:

    * **Attack a rival city, then MOVE IN to capture it** — an intact
      hostile city rides `game:cities` (see that event's own doc above)
      as a right-click ATTACK target exactly like an adjacent barbarian/
      camp (the `.Board` hook's own `orderMove/1`), and — when a
      friendly military unit adjacent to one is selected —
      `GameLive.UnitPanel` also renders an explicit "Attack" button per
      attackable city (`attackable_cities/2`, below), the same
      discoverable-button convention `unit_panel.ex`'s Found City/Build
      already establish (right-click alone is a harder-to-discover
      gesture for a brand-new mechanic). QA issue 7f91cff2: once that
      same city is `broken` (0 HP, `Siege.broken?/1`), both affordances
      swap from attack to MOVE — the right-click now `queue_move`s the
      selected unit onto the city's own tile (Civ-style occupation, "no
      range-flip — you commit and hold a body") instead of re-issuing a
      harmless attack, and the UnitPanel button relabels "Move In" and
      dispatches `"queue_move"`/`to_tile` instead of `"attack"`/
      `target_city_id`.
    * **Execute/Release a fallen garrison** — once `Game.
      captured_cities_visible_to/2` reports a captured city with a
      still-living defender, the top bar's "Captured Cities" dropdown
      (`captured_cities_panel/1`, below) renders the conqueror's own
      Execute/Release choice, wired straight to the existing
      `"resolve_garrison_fate"` handler.
    * **Issue / answer / refuse a call to arms** — the lord's own
      `vassals_panel`/`vassal_row` grows an "Issue Call to Arms" form
      (target drawn from `@known_players`, wired to `"issue_levy"`);
      the vassal's own status badge grows Answer/Refuse buttons while
      `levy_status` reads `:pending`, wired to `"answer_levy"`/
      `"refuse_levy"`.

  All three stay implicitly scoped to `Game.feudal_enabled?/0` — the
  underlying `Game` reads that power them
  (`enemy_cities_visible_to/2`, `captured_cities_visible_to/2`,
  `vassals/2`, `vassal_status/2`) all report empty/`nil` with the flag
  off, the same "no separate UI-side check needed" posture
  `Game.feudal_enabled?/0`'s own doc already establishes for the rest
  of this batch.

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
  alias BrokenOaths.Cities.Yields
  alias BrokenOaths.Game
  alias BrokenOaths.Players.Presence
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.{Generator, Globe, Regions, Weather}
  alias BrokenOathsWeb.GameLive.{BoardOverlays, FeudalTopBar, Modals, PlayView}

  @default_scale 700

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
        {yaw, pitch} = PlayView.camera_on(units, mesh)

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
            # QA issue 56ee521a/ffa66192: fog-filtered enemy cities
            # (hostile attack targets), the viewer's own captured
            # holdings (the garrison-fate choice), and whichever of
            # those the currently selected unit could actually attack
            # right now — all three real only once `feudal_enabled?`
            # ever produces anything to fill them.
            enemy_cities: [],
            captured_cities: [],
            attackable_cities: [],
            # QA issue 12bed1e4 — the "Shoot" affordance's own target
            # list (barbarian units/camps/hostile cities in range of a
            # selected Archer), same "real only once a unit is actually
            # selected" status `attackable_cities` above already has.
            shoot_targets: [],
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
            copper_access?: false,
            coastal?: false,
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
            # Stories 915/919: the rebel's own active-or-most-recent
            # Rebellion, every Rebellion raised against this player as
            # the FORMER LORD, and the read-only independence preview
            # (`nil` until `"open_independence_preview"` fires — see
            # that event's own doc). `declare_independence_lord_user_id`
            # is the two-step confirm's own transient UI flag (story
            # 915's own "confirming warning" step) — never persisted,
            # cleared the moment the flow commits or is cancelled.
            rebellion_status: Game.rebellion_status(world, user),
            rebellions_as_lord: Game.rebellions_as_lord(world, user),
            independence_preview: nil,
            declare_independence_lord_user_id: nil,
            # Story 916 (Pact of Broken Oaths): `pact` is `user`'s own
            # membership in a `:forming` conspiracy chat (`nil` while
            # they're not a member of one — see `Game.pact_view/2`'s
            # own doc for the secrecy masking every OTHER member's row
            # gets, criterion 7738), `pact_candidates` the fellow-vassal
            # invite roster the composer offers, `pact_panel_open?` its
            # own local toggle (mirrors `AlliancePanel`'s `open?`), and
            # `pact_informed`/`conspiracy_heat` the LORD's own side —
            # the warning banner once informed on, and the coarse
            # aggregate Oath Strain gauge (criterion 7742).
            pact: Game.pact_view(world, user),
            pact_candidates: Game.pact_candidates(world, user),
            pact_panel_open?: false,
            pact_informed: Game.pact_informed_notice(world, user),
            conspiracy_heat: Game.conspiracy_heat(world, user),
            # Story 909: cleared the next time either `"collect_bank"`/
            # `"upgrade_bank"` succeeds — same transient-error status
            # `city_error`/`order_error`/`combat_error`/`improvement_error`
            # already have (never DB-persisted, only ever lives on this
            # one connection's own socket).
            bank_error: nil,
            # QA issue bd93cc0a: same transient-error status as
            # `bank_error` above, for `"steward_queue_production"`/
            # `"steward_defend"`.
            steward_error: nil,
            # Story 909/910: unlike `vassals-list`/`vassal-status`
            # (naturally empty with the flag off, since nothing ever
            # creates a `Vassalage` row to power them), the Bank/Honor/
            # steward-log UI reads STRUCTURAL `Player` fields that exist
            # — at their inert defaults — on every player regardless of
            # the flag. `Game.feudal_enabled?/0` is read once here and
            # gates every one of those NEW badges/panels directly in the
            # template, keeping prod's own board looking exactly as it
            # does today until this batch ships for real.
            feudal_enabled?: Game.feudal_enabled?(),
            yaw: yaw,
            pitch: pitch,
            scale: @default_scale,
            page_title: world.name
          )
          |> refresh_board()

        {:ok, socket}
    end
  end

  # Story 909/910's own eligibility check (`BrokenOaths.Players.Presence.
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

  # A left click on a tile is always resolved to "the unit standing
  # there" client-side (the board hook's `click/1`), but since v0.2.1's
  # field stacking (a non-combat unit sharing a tile with an escort of
  # the SAME owner — see `BrokenOaths.Units.Unit`'s own moduledoc) a
  # single tile can now hold two of the player's own units — QA issue
  # d403faa6, "can't pick stacked unit". The hook sends the CLICKED
  # tile's id alongside its own best-guess `unit_id`; when that tile
  # carries more than one of THIS player's own units, `next_unit_in_stack/2`
  # decides which one actually gets selected: the Civ convention is
  # "cycle to the next one" on a re-click of an already-selected tile,
  # wrapping back to the first past the last. `socket.assigns.units`
  # (fog-filtered, see the moduledoc's `game:units` doc) never carries
  # ownership on each entry, so the tile's own stack is read fresh off
  # `Game.player_units/2` — already scoped to this player's own units
  # — rather than trying to infer ownership client-side. A click on a
  # tile with only a foreign (visible enemy) unit, or with no `tile_id`
  # at all (every direct `render_hook` call in this codebase's own
  # tests), falls straight through to the plain by-id lookup —
  # unchanged from before this fix.
  def handle_event("select_unit", %{"unit_id" => unit_id} = params, socket) do
    unit_id = PlayView.parse_id(unit_id)
    tile_id = params |> Map.get("tile_id") |> PlayView.parse_id()

    %{
      units: units,
      cities: cities,
      world: world,
      user: user,
      selected_unit_id: current_unit_id,
      selected_city_id: current_city_id
    } = socket.assigns

    stack = if tile_id, do: PlayView.owned_stack_on_tile(world, user, tile_id), else: []
    city_on_tile = tile_id && Enum.find(cities, &(&1.tile_id == tile_id))

    socket =
      case PlayView.next_tile_selection(stack, city_on_tile, current_unit_id, current_city_id) do
        {:city, city} ->
          apply_city_panel(socket, city)

        {:unit, unit} ->
          apply_unit_panel(socket, unit, unit.id)

        :none ->
          unit = Enum.find(units, &(&1.id == unit_id))
          apply_unit_panel(socket, unit, (unit && unit.id) || unit_id)
      end

    {:noreply, socket}
  end

  # A left click on open ground (no unit, no owned city — the board
  # hook's `click/1` fallthrough) opens a small tile panel: terrain,
  # base yields, and any known improvement. Mutually exclusive with the
  # unit/city panels, same one-side-panel rule. Only known tiles ever
  # reach the client, so no fog check is needed here beyond membership
  # in the pushed window.
  def handle_event("select_tile", %{"tile_id" => tile_id}, socket) do
    %{world: world, improvements: improvements, player_research: player_research} = socket.assigns
    tile_id = PlayView.parse_id(tile_id)
    terrain = Regions.terrain(world, tile_id)
    resource = PlayView.visible_resource(world, tile_id, player_research)
    yields = Yields.tile_yield(terrain, resource)
    improvement = Enum.find(improvements, &(&1.tile_id == tile_id))

    socket =
      assign(socket,
        selected_tile: %{
          id: tile_id,
          terrain: PlayView.terrain_label(terrain),
          food: yields.food,
          production: yields.production,
          improvement: improvement,
          resource: resource
        },
        selected_unit_id: nil,
        selected_unit: nil,
        selected_order: nil,
        attackable_cities: [],
        shoot_targets: [],
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
    %{world: world, user: user, cities: cities} = socket.assigns
    city_id = PlayView.parse_id(city_id)
    city = Enum.find(cities, &(&1.id == city_id))

    socket =
      assign(socket,
        selected_city_id: city_id,
        selected_city: city,
        assignable_tiles: PlayView.assignable_tiles(world, city),
        copper_access?: Game.copper_access?(world, user),
        coastal?: PlayView.coastal?(world, city),
        city_error: nil,
        selected_unit_id: nil,
        selected_unit: nil,
        selected_tile: nil,
        attackable_cities: [],
        shoot_targets: [],
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
    camp_id = PlayView.parse_id(camp_id)
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
        attackable_cities: [],
        shoot_targets: [],
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
        attackable_cities: [],
        shoot_targets: [],
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

    case Game.found_city(world, user, PlayView.parse_id(unit_id)) do
      :ok ->
        {:noreply, socket |> assign(city_error: nil) |> maybe_flash_barbarian_warning()}

      {:error, reason} ->
        {:noreply, assign(socket, city_error: PlayView.city_error_message(reason))}
    end
  end

  def handle_event("queue_production", %{"city_id" => city_id, "item" => item}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.queue_production(world, user, PlayView.parse_id(city_id), item) do
      :ok ->
        {:noreply, assign(socket, city_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, city_error: PlayView.city_error_message(reason))}
    end
  end

  def handle_event(
        "cancel_production_item",
        %{"city_id" => city_id, "item_id" => item_id},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.cancel_production_item(
           world,
           user,
           PlayView.parse_id(city_id),
           PlayView.parse_id(item_id)
         ) do
      :ok ->
        {:noreply, assign(socket, city_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, city_error: PlayView.city_error_message(reason))}
    end
  end

  def handle_event(
        "reorder_production_item",
        %{"city_id" => city_id, "item_id" => item_id},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.reorder_production_item(
           world,
           user,
           PlayView.parse_id(city_id),
           PlayView.parse_id(item_id)
         ) do
      :ok ->
        {:noreply, assign(socket, city_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, city_error: PlayView.city_error_message(reason))}
    end
  end

  # `from_tile_id`/`to_tile_id` are each optional (see `Game.assign_worked_tile/5`):
  # a plain click, unlike a spec's render_hook, only ever supplies one of
  # the two (unwork vs. work), so a missing key means nil, not an error.
  def handle_event("assign_worked_tile", params, socket) do
    %{world: world, user: user} = socket.assigns
    city_id = PlayView.parse_id(params["city_id"])
    from_tile = PlayView.parse_id(params["from_tile_id"])
    to_tile = PlayView.parse_id(params["to_tile_id"])

    case Game.assign_worked_tile(world, user, city_id, from_tile, to_tile) do
      :ok ->
        {:noreply, assign(socket, city_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, city_error: PlayView.city_error_message(reason))}
    end
  end

  def handle_event("rename_city", %{"city" => %{"name" => name}}, socket) do
    %{world: world, user: user, selected_city_id: city_id} = socket.assigns

    case Game.rename_city(world, user, city_id, name) do
      :ok ->
        {:noreply, assign(socket, city_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, city_error: PlayView.city_error_message(reason))}
    end
  end

  def handle_event("start_improvement", %{"unit_id" => unit_id, "kind" => kind}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.start_improvement(world, user, PlayView.parse_id(unit_id), kind) do
      :ok ->
        # Refresh inline (not just via the async :improvements_changed
        # broadcast) so the dig-progress badge appears in the same
        # render as the click — issue b5cc4ae9.
        {:noreply, socket |> assign(improvement_error: nil) |> refresh_board()}

      {:error, reason} ->
        {:noreply, assign(socket, improvement_error: PlayView.improvement_error_message(reason))}
    end
  end

  # QA issue 8aa2c571 — a worker mid-dig had no way to back out of it.
  # Same inline-refresh pattern as `start_improvement` above: the
  # dig-progress badge (and its Cancel button) must disappear in the
  # SAME render as the click, not wait on the async broadcast.
  def handle_event("cancel_improvement", %{"unit_id" => unit_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.cancel_improvement(world, user, PlayView.parse_id(unit_id)) do
      :ok ->
        {:noreply, socket |> assign(improvement_error: nil) |> refresh_board()}

      {:error, reason} ->
        {:noreply, assign(socket, improvement_error: PlayView.improvement_error_message(reason))}
    end
  end

  # Right-clicks arrive as the clicked point on the unit sphere, not a
  # tile id: the client's tile window is fog-filtered, so it cannot name
  # a tile it has never seen. The server resolves which tile the player
  # aimed at — orders into and through the fog of war are legal, and no
  # hidden tile data ever travels to the client to make them so.
  def handle_event("queue_move", %{"unit_id" => unit_id, "to_point" => [x, y, z]}, socket)
      when is_number(x) and is_number(y) and is_number(z) do
    to_tile = PlayView.nearest_tile(socket.assigns.mesh, {x, y, z})
    handle_event("queue_move", %{"unit_id" => unit_id, "to_tile" => to_tile}, socket)
  end

  # phx-value-* params arrive as STRINGS from real DOM buttons but as
  # native integers from specs' render_hook — every id must go through
  # parse_id/1 before touching Game's integer-keyed state (same QA
  # issue class documented on found_city/2 above; queue_move had the
  # identical gap — a string unit_id silently failed as :not_owner,
  # since `Map.get(state.units, unit_id)` never matches an integer key
  # against a string). `to_tile` gets the same treatment (QA issue
  # 7f91cff2) — until `UnitPanel`'s own "Move In" button, `to_tile`
  # only ever arrived pre-parsed as a real integer (the `to_point`
  # clause above resolves one via `nearest_tile/2`; every existing spec
  # call goes through `render_hook`, which never stringifies). A real
  # DOM button's `phx-value-to_tile` is a STRING, and `do_queue_move/4`
  # hard-requires `is_integer(to_tile)` — without this, the Move In
  # button would silently no-op as `{:error, :invalid_tile}`.
  def handle_event("queue_move", %{"unit_id" => unit_id, "to_tile" => to_tile}, socket) do
    %{world: world, user: user} = socket.assigns
    unit_id = PlayView.parse_id(unit_id)
    to_tile = PlayView.parse_id(to_tile)

    case Game.queue_move(world, user, unit_id, to_tile) do
      {:ok, %{path: path}} ->
        socket =
          socket
          |> assign(order_error: nil)
          |> push_event("game:path", %{unit_id: unit_id, tiles: path})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, order_error: PlayView.order_error_message(reason))}
    end
  end

  # Resolves immediately, like queue_move — the result carries this
  # turn's damage_dealt/damage_taken (story 891, criterion 7540), which
  # this handler pushes straight back to the attacker's own view rather
  # than waiting on the broadcast every other mutation relies on
  # (mirroring queue_move's direct "game:path" push above).
  def handle_event("attack", %{"unit_id" => unit_id, "target_unit_id" => target_unit_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.attack(world, user, PlayView.parse_id(unit_id), PlayView.parse_id(target_unit_id)) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: PlayView.combat_error_message(reason))}
    end
  end

  # Story 894: attacking a barbarian camp reuses the "attack" hook, with
  # `target_camp_id` instead of `target_unit_id` (a camp is not a
  # `Game.Unit`) — same immediate-resolution, direct-push shape as the
  # unit-target clause above. `damage_taken` is always 0 (camps never
  # counter-attack, see `Game.Combat.camp_damage/2`).
  def handle_event("attack", %{"unit_id" => unit_id, "target_camp_id" => target_camp_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.attack_camp(
           world,
           user,
           PlayView.parse_id(unit_id),
           PlayView.parse_id(target_camp_id)
         ) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: PlayView.combat_error_message(reason))}
    end
  end

  # Story 895: attacking a city reuses the "attack" hook, with
  # `target_city_id` instead of `target_unit_id`/`target_camp_id` — same
  # immediate-resolution, direct-push shape as both clauses above.
  # `damage_taken` is the attacker's own counter-attack damage from the
  # city's strongest garrisoned defender (0 if undefended).
  def handle_event("attack", %{"unit_id" => unit_id, "target_city_id" => target_city_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.attack_city(
           world,
           user,
           PlayView.parse_id(unit_id),
           PlayView.parse_id(target_city_id)
         ) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: PlayView.combat_error_message(reason))}
    end
  end

  # QA issue 12bed1e4 "Archers don't have a shoot action" — the Archer's
  # own ranged "shoot" surface, same three-clause dispatch-by-key shape
  # `"attack"` above already uses (`target_unit_id`/`target_camp_id`/
  # `target_city_id`), same direct `"game:combat"` push. `damage_taken`
  # is always 0 — the whole point of shooting instead of marching in.
  def handle_event("shoot", %{"unit_id" => unit_id, "target_unit_id" => target_unit_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.shoot(world, user, PlayView.parse_id(unit_id), PlayView.parse_id(target_unit_id)) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: PlayView.combat_error_message(reason))}
    end
  end

  # QA issue 12bed1e4 — the ranged sibling of the `target_camp_id`
  # "attack" clause above.
  def handle_event("shoot", %{"unit_id" => unit_id, "target_camp_id" => target_camp_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.shoot_camp(
           world,
           user,
           PlayView.parse_id(unit_id),
           PlayView.parse_id(target_camp_id)
         ) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: PlayView.combat_error_message(reason))}
    end
  end

  # QA issue 12bed1e4 — the ranged sibling of the `target_city_id`
  # "attack" clause above.
  def handle_event("shoot", %{"unit_id" => unit_id, "target_city_id" => target_city_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.shoot_city(
           world,
           user,
           PlayView.parse_id(unit_id),
           PlayView.parse_id(target_city_id)
         ) do
      {:ok, %{damage_dealt: dealt, damage_taken: taken}} ->
        socket =
          socket
          |> assign(combat_error: nil)
          |> push_event("game:combat", %{damage_dealt: dealt, damage_taken: taken})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: PlayView.combat_error_message(reason))}
    end
  end

  # Story 920 — the Fortify stance's own single-target LiveView surface
  # (`Units.Unit.fortify/3`): same `combat_error`-flash shape
  # `"attack"`/`"shoot"` above already use (fortifying is itself a
  # combat-domain command), just no `"game:combat"` push — nothing was
  # struck. `:units_changed` (broadcast by `WorldServer`'s own
  # `:fortify` handler) is what actually bumps
  # `@selected_unit.fortified_turns` and reveals the badge, the same
  # refresh path every other unit command already relies on.
  def handle_event("fortify", %{"unit_id" => unit_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.fortify(world, user, PlayView.parse_id(unit_id)) do
      :ok ->
        {:noreply, assign(socket, combat_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: PlayView.combat_error_message(reason))}
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

    case Game.choose_hidden_agenda(world, user, PlayView.parse_agenda(agenda)) do
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

    case Game.set_tribute_rate(
           world,
           user,
           PlayView.parse_id(vassal_user_id),
           PlayView.parse_percent(rate)
         ) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Story 908: the lord's own call to arms against a third player —
  # `"share"` arrives as the pledged fraction (0, 1] directly, not a
  # percentage (mirrors `Levy.pledged_share`'s own scale).
  def handle_event(
        "issue_levy",
        %{
          "vassal_user_id" => vassal_user_id,
          "target_user_id" => target_user_id,
          "share" => share
        },
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.issue_levy(
           world,
           user,
           PlayView.parse_id(vassal_user_id),
           PlayView.parse_id(target_user_id),
           PlayView.parse_fraction(share)
         ) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("answer_levy", %{"lord_user_id" => lord_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.answer_levy(world, user, PlayView.parse_id(lord_user_id)) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("refuse_levy", %{"lord_user_id" => lord_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.refuse_levy(world, user, PlayView.parse_id(lord_user_id)) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Story 913: the lord's one-off gift to a vassal — `"gift"` names
  # what was gifted (flavor only; every gift applies the same
  # `OathStrain.ease_gift/1` regardless of what it names).
  def handle_event(
        "gift_vassal",
        %{"vassal_user_id" => vassal_user_id, "gift" => _gift},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.gift_vassal(world, user, PlayView.parse_id(vassal_user_id)) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Story 913: the lord and a vassal declaring a shared enemy.
  def handle_event(
        "declare_shared_enemy",
        %{"vassal_user_id" => vassal_user_id, "enemy_user_id" => enemy_user_id},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.declare_shared_enemy(
           world,
           user,
           PlayView.parse_id(vassal_user_id),
           PlayView.parse_id(enemy_user_id)
         ) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Story 913 (criterion 7722): the vassal's own narrow seam for
  # marking their lord's Protection Pact unhonored — see
  # `BrokenOaths.Game.mark_pact_unhonored/3`'s own doc for how this
  # differs from the real story 914 broken-pact resolution.
  def handle_event("mark_pact_unhonored", %{"lord_user_id" => lord_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.mark_pact_unhonored(world, user, PlayView.parse_id(lord_user_id)) do
      :ok -> {:noreply, refresh_vassalage(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # -------------------------------------------------------------------
  # Rebellion (stories 915/919)
  # -------------------------------------------------------------------

  # Story 915, criterion 7732 — read-only inspection: computes (never
  # commits) which of `lord_user_id`'s occupied cities would rise and
  # the predicted temporary army size, using the SAME formula
  # `"confirm_declare_independence"` below commits with. Opening the
  # preview alone changes nothing — no `Game` write happens here.
  def handle_event("open_independence_preview", %{"lord_user_id" => lord_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    preview =
      case Game.independence_preview(world, user, PlayView.parse_id(lord_user_id)) do
        {:ok, result} -> result
        {:error, _reason} -> nil
      end

    {:noreply, assign(socket, independence_preview: preview)}
  end

  # Story 915 — step one of the two-step confirm: raises the confirming
  # warning, commits nothing (mirrors story 902/903's own
  # `"select_research"`/`"bronze_working_confirm"` pattern).
  #
  # Story 917 — the SAME event, one narrow exception: once the target
  # lord's own Lord unit is already dead ("seize the moment"), there is
  # nothing further to warn about — the death itself was the dramatic
  # beat — so this commits IMMEDIATELY instead, skipping the warning
  # modal. `Game.lord_fallen?/2` is read fresh here (never off
  # `socket.assigns.vassal_status`, which can go stale: the immediate,
  # out-of-tick combat path that can kill a lord never broadcasts
  # `:vassals_changed` on its own) so an already-connected socket still
  # gets this right the instant it clicks.
  def handle_event("declare_independence", %{"lord_user_id" => lord_user_id}, socket) do
    %{world: world} = socket.assigns
    lord_id = PlayView.parse_id(lord_user_id)

    if Game.lord_fallen?(world, lord_id) do
      do_confirm_declare_independence(socket, lord_id)
    else
      {:noreply, assign(socket, declare_independence_lord_user_id: lord_id)}
    end
  end

  # Story 919's own convenience entry point: fired with NO params — "a
  # player has at most one lord, so no target disambiguation is
  # needed" (mirrors `"answer_levy"`/`"refuse_levy"`). Commits
  # IMMEDIATELY, skipping the two-step warning above — there is no
  # separate preview open to bypass when this is invoked directly.
  def handle_event("declare_independence", %{}, socket) do
    case socket.assigns.vassal_status do
      %{lord_user_id: lord_user_id} -> do_confirm_declare_independence(socket, lord_user_id)
      _no_lord -> {:noreply, socket}
    end
  end

  # Story 915 — step two: actually severs the oath, resolves risings,
  # spawns the temporary army, and opens the war.
  def handle_event("confirm_declare_independence", %{"lord_user_id" => lord_user_id}, socket) do
    do_confirm_declare_independence(socket, PlayView.parse_id(lord_user_id))
  end

  def handle_event("declare_independence_cancel", _params, socket) do
    {:noreply, assign(socket, declare_independence_lord_user_id: nil)}
  end

  # Story 919, criterion 7754 — either side offers a negotiated peace.
  # `"outcome"` is `"independence"` or `"restored_vassal"`;
  # `"reparations_gold"` is optional (blank/missing reads as no
  # reparations).
  def handle_event(
        "offer_peace",
        %{"counterparty_user_id" => counterparty_user_id, "outcome" => outcome} = params,
        socket
      ) do
    %{world: world, user: user} = socket.assigns
    reparations_gold = PlayView.parse_optional_int(Map.get(params, "reparations_gold"))

    case Game.offer_peace(
           world,
           user,
           PlayView.parse_id(counterparty_user_id),
           outcome,
           reparations_gold
         ) do
      :ok -> {:noreply, refresh_rebellions(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("accept_peace", %{"counterparty_user_id" => counterparty_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.accept_peace(world, user, PlayView.parse_id(counterparty_user_id)) do
      :ok -> {:noreply, socket |> refresh_vassalage() |> refresh_rebellions() |> refresh_board()}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("reject_peace", %{"counterparty_user_id" => counterparty_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.reject_peace(world, user, PlayView.parse_id(counterparty_user_id)) do
      :ok -> {:noreply, refresh_rebellions(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # -------------------------------------------------------------------
  # Coordinated Rebellion — Pact of Broken Oaths (story 916)
  # -------------------------------------------------------------------

  # Mirrors `AlliancePanel`'s own `"toggle_alliance_panel"` — this
  # composer lives directly on `Play` (not a `LiveComponent`) since
  # every OTHER pact event does too (the invented contract fires
  # `render_hook` straight at this LiveView, never a `phx-target`).
  def handle_event("toggle_pact_panel", _params, socket) do
    {:noreply, assign(socket, pact_panel_open?: !socket.assigns.pact_panel_open?)}
  end

  # Criterion 7737 — a vassal opens a Pact of Broken Oaths against
  # their own lord, naming a strike turn (turn BOUNDARIES from right
  # now — see `Game.open_pact_chat/4`'s own doc) and inviting fellow
  # vassals into it.
  def handle_event(
        "open_pact_chat",
        %{"strike_turn" => strike_turn, "invitee_user_ids" => invitee_user_ids},
        socket
      ) do
    %{world: world, user: user} = socket.assigns
    invitee_ids = Enum.map(List.wrap(invitee_user_ids), &PlayView.parse_id/1)

    case Game.open_pact_chat(world, user, PlayView.parse_id(strike_turn), invitee_ids) do
      {:ok, _pact} -> {:noreply, refresh_pact(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("pact_commit", _params, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.pact_commit(world, user) do
      {:ok, _member} -> {:noreply, refresh_pact(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Story 916, criterion 7742 — reversible any time before the strike:
  # a committed conspirator can still back out once the lord starts
  # making concessions.
  def handle_event("pact_decline", _params, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.pact_decline(world, user) do
      {:ok, _member} -> {:noreply, refresh_pact(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Criterion 7741 — secretly tips the lord off; the informer's own
  # identity never reaches any OTHER member (`Game.pact_view/2`'s own
  # masking already keeps a plain member row from ever naming them).
  def handle_event("pact_inform", _params, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.pact_inform(world, user) do
      {:ok, _member} -> {:noreply, refresh_pact(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # The lord's own pre-emption levers, available once warned
  # (criterion 7741) — brace fully heals every one of her own cities.
  def handle_event("brace_defenses", _params, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.brace_defenses(world, user) do
      :ok -> {:noreply, refresh_board(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Reposition fully heals her own Lord unit.
  def handle_event("reposition_lord", _params, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.reposition_lord(world, user) do
      :ok -> {:noreply, refresh_board(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Buying off conspirators broadly eases EVERY vassal's Oath Strain at
  # once — the lord still can't target just the plotters, since the
  # roster stays secret even once informed.
  def handle_event("buy_off_conspirators", _params, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.buy_off_conspirators(world, user) do
      :ok -> {:noreply, socket |> refresh_vassalage() |> refresh_pact()}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Criterion 7742 — a TARGETED concession, alongside the real
  # `"set_tribute_rate"` lever already below.
  def handle_event("honor_protection_call", %{"vassal_user_id" => vassal_user_id}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.honor_protection_call(world, user, PlayView.parse_id(vassal_user_id)) do
      :ok -> {:noreply, socket |> refresh_vassalage() |> refresh_pact()}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # -------------------------------------------------------------------
  # Gold Bank (story 909)
  # -------------------------------------------------------------------

  # The deliberate engagement tap — sweeps the ENTIRE bank into the
  # treasury. Never refused outright (an empty bank just moves nothing),
  # so this never needs its own error branch.
  def handle_event("collect_bank", _params, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.collect_bank(world, user) do
      :ok -> {:noreply, socket |> assign(bank_error: nil) |> refresh_board()}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # Raises the bank's own cap for a gold cost — refused outright (no
  # partial charge) when the treasury can't cover it.
  def handle_event("upgrade_bank", _params, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.upgrade_bank(world, user) do
      :ok ->
        {:noreply, socket |> assign(bank_error: nil) |> refresh_board()}

      {:error, reason} ->
        {:noreply, assign(socket, bank_error: PlayView.bank_error_message(reason))}
    end
  end

  # -------------------------------------------------------------------
  # Feudal Stewardship (story 910)
  # -------------------------------------------------------------------

  # A steward sweeps an offline household member's own bank — pure
  # stewardship, entirely to the OWNER; refused unless eligible AND the
  # owner is genuinely offline. Refreshes THIS steward's own board
  # (their own Honor never moves here — only `"steward_defend"`'s own
  # overreach case can ding it — but re-pulling costs nothing and keeps
  # every steward action on the same "refresh after acting" footing).
  def handle_event("steward_collect_bank", %{"owner_user_id" => owner_user_id}, socket) do
    %{world: world, user: user} = socket.assigns
    Game.steward_collect_bank(world, user, PlayView.parse_id(owner_user_id))
    {:noreply, refresh_board(socket)}
  end

  # Sets an offline household member's own production queue —
  # constructive-only, mirrors `"queue_production"`'s own `"city_id"`/
  # `"item"` param shape, scoped through stewardship eligibility. QA
  # issue bd93cc0a: `@vassal.steward`/`@alliance.steward`'s own
  # per-city catalog is the click-through source for `item` — always
  # already whitelist-filtered client-side (`Stewardship.
  # constructive_item?/1`), so `:not_constructive` never fires from a
  # real click, only ever a direct `attempt_event`/spex dispatch.
  def handle_event(
        "steward_queue_production",
        %{"owner_user_id" => owner_user_id, "city_id" => city_id, "item" => item},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.steward_queue_production(
           world,
           user,
           PlayView.parse_id(owner_user_id),
           PlayView.parse_id(city_id),
           item
         ) do
      :ok ->
        {:noreply, socket |> assign(steward_error: nil) |> refresh_after_steward_action()}

      {:error, reason} ->
        {:noreply, assign(socket, steward_error: PlayView.steward_error_message(reason))}
    end
  end

  # "No cancel-griefing" — always refused, whitelist enforced by
  # structural absence (`BrokenOaths.Feudal.Stewardship`'s own moduledoc).
  def handle_event(
        "steward_cancel_production_item",
        %{"owner_user_id" => owner_user_id, "city_id" => city_id, "item_id" => item_id},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    Game.steward_cancel_production_item(
      world,
      user,
      PlayView.parse_id(owner_user_id),
      PlayView.parse_id(city_id),
      PlayView.parse_id(item_id)
    )

    {:noreply, refresh_board(socket)}
  end

  # "No disbanding" — always refused, same structural-absence status
  # above.
  def handle_event(
        "steward_disband_unit",
        %{"owner_user_id" => owner_user_id, "unit_id" => unit_id},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    Game.steward_disband_unit(
      world,
      user,
      PlayView.parse_id(owner_user_id),
      PlayView.parse_id(unit_id)
    )

    {:noreply, refresh_board(socket)}
  end

  # "Normally stewards CANNOT move units" — always refused; the
  # default-closed baseline `"steward_defend"`'s own emergency exception
  # opens against.
  def handle_event(
        "steward_queue_move",
        %{"owner_user_id" => owner_user_id, "unit_id" => unit_id, "to_tile" => to_tile},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    Game.steward_queue_move(
      world,
      user,
      PlayView.parse_id(owner_user_id),
      PlayView.parse_id(unit_id),
      to_tile
    )

    {:noreply, refresh_board(socket)}
  end

  # EMERGENCY DEFENSE — the one sanctioned exception: refused unless the
  # offline owner is genuinely under attack, and even then only for a
  # strictly adjacent, defensive reposition. An eligible steward who
  # overreaches the destination mid-emergency is provable sabotage —
  # refused, logged, AND dings the STEWARD's own Honor (this refresh is
  # what picks that up on THIS session). `to_tile` goes through
  # `parse_id/1` (QA issue bd93cc0a) exactly like every other DOM-button
  # `phx-value` tile id — a real click's `phx-value-to_tile` arrives as
  # a STRING, and without this, `Stewardship.defend_target_allowed?/3`'s
  # own `to_tile in adjacent_tile_ids` could never match an integer
  # list, so EVERY real click-through order would misfire as provable
  # sabotage and wrongly ding the steward's own Honor.
  def handle_event(
        "steward_defend",
        %{"owner_user_id" => owner_user_id, "unit_id" => unit_id, "to_tile" => to_tile},
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    case Game.steward_defend(
           world,
           user,
           PlayView.parse_id(owner_user_id),
           PlayView.parse_id(unit_id),
           PlayView.parse_id(to_tile)
         ) do
      :ok ->
        {:noreply, socket |> assign(steward_error: nil) |> refresh_after_steward_action()}

      {:error, reason} ->
        {:noreply,
         assign(socket, steward_error: PlayView.steward_error_message(reason))
         |> refresh_after_steward_action()}
    end
  end

  # "Never to launch aggression" — always refused, even mid-emergency.
  def handle_event(
        "steward_attack",
        %{
          "owner_user_id" => owner_user_id,
          "unit_id" => unit_id,
          "target_camp_id" => target_camp_id
        },
        socket
      ) do
    %{world: world, user: user} = socket.assigns

    Game.steward_attack(
      world,
      user,
      PlayView.parse_id(owner_user_id),
      PlayView.parse_id(unit_id),
      PlayView.parse_id(target_camp_id)
    )

    {:noreply, refresh_board(socket)}
  end

  # Story 899, criterion 7601: a Known Players row's "chat-link"
  # affordance opens the chat panel straight onto that contact's
  # thread — full conversation-loading behavior lands with
  # `GameLive.ChatPanel` (story 900); this just carries which contact
  # was picked, in `:chat_target_user_id`, into that component's own
  # assigns.
  def handle_event("open_chat", %{"user_id" => user_id}, socket) do
    {:noreply, assign(socket, chat_open: true, chat_target_user_id: PlayView.parse_id(user_id))}
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
  #
  # Issue 133b4893 (the expanded, prerequisite-gated tree): Bronze
  # Working now requires Mining first, so its confirm warning only ever
  # surfaces once `Research.prereqs_met?/2` says it's actually
  # researchable — a locked Bronze Working row (Mining not done) is a
  # silent no-op here, same as `"select_research"`'s own `{:error, _}`
  # branch below, rather than popping a warning for a pick that would
  # just be refused anyway. `"bronze_working_confirm"` itself no longer
  # blindly pattern-matches `:ok` — a race (state changed between the
  # click opening the warning and the confirm click landing) now
  # degrades to the same silent no-op instead of crashing the view.
  def handle_event("toggle_tech_panel", _params, socket) do
    {:noreply, assign(socket, tech_panel_open?: !socket.assigns.tech_panel_open?)}
  end

  def handle_event("select_research", %{"tech" => "bronze_working"}, socket) do
    if Research.prereqs_met?(socket.assigns.player_research, :bronze_working) do
      {:noreply, assign(socket, bronze_working_pending?: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_research", %{"tech" => tech}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.set_research(world, user, PlayView.parse_tech(tech)) do
      :ok -> {:noreply, refresh_research(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("bronze_working_confirm", _params, socket) do
    %{world: world, user: user} = socket.assigns

    socket =
      case Game.set_research(world, user, :bronze_working) do
        :ok -> refresh_research(socket)
        {:error, _reason} -> socket
      end

    {:noreply, assign(socket, bronze_working_pending?: false)}
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
  # (`Diplomacy.Discovery`) broadcasts this world-wide, once per side of a
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

  # Story 915, criterion 7736: the FORMER LORD's own notification the
  # moment a vassal declares independence — names the rebel and lists
  # exactly which cities the SAME deterministic formula the rebel's own
  # preview already showed marked will-rise.
  def handle_info({:rebellion_declared, user_id, message, risen_city_ids}, socket) do
    if user_id == socket.assigns.user.id do
      socket =
        socket
        |> refresh_rebellions()
        |> push_event("game:rebellion_declared", %{
          message: message,
          risen_city_ids: risen_city_ids
        })

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
  # already establish. Stories 915/919 ride this SAME broadcast for
  # every Rebellion mutation too, so `:rebellion_status`/`:rebellions_
  # as_lord` are refreshed right alongside. Story 916's own
  # `conspiracy_heat` reads straight off the SAME `Vassalage.oath_strain`
  # figures, so it rides along here too.
  def handle_info(:vassals_changed, socket) do
    {:noreply, socket |> refresh_vassalage() |> refresh_rebellions() |> refresh_pact()}
  end

  # Story 916 — every pact chat mutation (a new pact opened, a member's
  # own commit/decline/inform) broadcasts this world-wide; every
  # connected view re-pulls its own masked `:pact`/`:pact_candidates`/
  # `:pact_informed` reads, same "every connected view re-pulls its own
  # state" pattern `:vassals_changed` already establishes.
  def handle_info(:pact_changed, socket) do
    {:noreply, refresh_pact(socket)}
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

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
    # QA issue 56ee521a/ffa66192 — see this module's own "Siege /
    # Garrison-fate / Levy UI" doc section: both real only once `Game.
    # feudal_enabled?/0` does, empty otherwise.
    enemy_cities = Game.enemy_cities_visible_to(world, user)
    captured_cities = Game.captured_cities_visible_to(world, user)
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
      allowed_improvements:
        PlayView.worker_allowed_improvements(world, selected_unit, player_research),
      current_dig: PlayView.worker_current_dig(improvements, selected_unit),
      attackable_cities: PlayView.attackable_cities(world, selected_unit, enemy_cities),
      shoot_targets: PlayView.shoot_targets(world, selected_unit, units, camps, enemy_cities),
      enemy_cities: enemy_cities,
      captured_cities: captured_cities,
      selected_city: selected_city,
      assignable_tiles: PlayView.assignable_tiles(world, selected_city),
      copper_access?: Game.copper_access?(world, user),
      coastal?: PlayView.coastal?(world, selected_city),
      selected_camp: selected_camp,
      known_players: Game.known_players(world, user),
      player_stats: Game.player_stats(world, user),
      player_research: player_research,
      # Story 909/910: the bank badges, Honor figure, and the owner's
      # own steward-action log — re-pulled on every board refresh (the
      # same "single source of truth, re-fetched on every signal" status
      # `gold`/`known_players` already have above), so an offline
      # accrual/collect/upgrade/steward action never lags behind a
      # reconnect or turn boundary.
      bank: Game.bank(world, user),
      honor: Game.honor(world, user),
      steward_log: Game.steward_log(world, user),
      # Stories 922/923: `GameLive.ProgressPanel`'s own "Gold/turn"
      # line — same "single source of truth, re-fetched on every
      # signal" status `bank` above already has, so a queued unit's
      # upkeep (or a completed Granary's) shows up the instant it
      # changes `cities`/`units`, not just at the next turn boundary.
      gold_per_turn: Game.gold_per_turn(world, user)
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
    player_research = socket.assigns.player_research
    enemy_cities = Map.get(socket.assigns, :enemy_cities, [])

    known = Enum.uniq(visible ++ explored)
    tiles = Enum.map(known, &PlayView.tile_row(&1, mesh, terrain_map))
    levels = Weather.map(world.seed, mesh)

    city_markers =
      Enum.map(cities, &PlayView.city_marker/1) ++
        Enum.map(enemy_cities, &PlayView.enemy_city_marker/1)

    socket
    |> push_event("game:window", %{tiles: tiles})
    |> push_event("game:visibility", %{visible: visible, explored: explored})
    |> push_event("game:units", %{units: units})
    |> push_event("game:cities", %{cities: city_markers})
    |> push_camps(camps)
    |> push_improvements(improvements)
    |> push_resources(PlayView.known_resources(known, world, player_research))
    |> push_event("globe3d:airspace", %{
      levels: levels,
      arc: Float.round(1.1071 / mesh.frequency, 5)
    })
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

  # -------------------------------------------------------------------
  # Vassalage / Tribute helpers (stories 906/907/908)
  # -------------------------------------------------------------------

  defp resolve_garrison_fate(socket, city_id, choice) do
    %{world: world, user: user} = socket.assigns

    case Game.resolve_garrison_fate(world, user, PlayView.parse_id(city_id), choice) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, combat_error: PlayView.combat_error_message(reason))}
    end
  end

  # Single source of truth for `:vassals`/`:vassal_status` — re-pulled
  # inline by every command that can change either (mirrors
  # `refresh_research/1`'s own "re-fetch on every signal" status) and by
  # the `:vassals_changed`/`:new_vassal`/`:vassalized` broadcasts.
  defp refresh_vassalage(socket) do
    %{world: world, user: user} = socket.assigns

    assign(socket,
      vassals: Game.vassals(world, user),
      vassal_status: Game.vassal_status(world, user)
    )
  end

  # Stories 915/919: single source of truth for `:rebellion_status`/
  # `:rebellions_as_lord` — re-pulled inline by every command that can
  # change either and by the `:vassals_changed` broadcast every
  # Rebellion mutation already rides alongside.
  defp refresh_rebellions(socket) do
    %{world: world, user: user} = socket.assigns

    assign(socket,
      rebellion_status: Game.rebellion_status(world, user),
      rebellions_as_lord: Game.rebellions_as_lord(world, user)
    )
  end

  # Story 916: single source of truth for `:pact`/`:pact_candidates`/
  # `:pact_informed`/`:conspiracy_heat` — re-pulled inline by every
  # pact-chat command and by the `:pact_changed`/`:vassals_changed`
  # broadcasts, same "re-fetch on every signal" status
  # `refresh_vassalage/1` already has.
  defp refresh_pact(socket) do
    %{world: world, user: user} = socket.assigns

    assign(socket,
      pact: Game.pact_view(world, user),
      pact_candidates: Game.pact_candidates(world, user),
      pact_informed: Game.pact_informed_notice(world, user),
      conspiracy_heat: Game.conspiracy_heat(world, user)
    )
  end

  # Story 915 — the shared commit path both `"declare_independence"`
  # (no-params convenience) and `"confirm_declare_independence"` (the
  # two-step flow's own second half) land on: the rebel's own
  # `"game:rebellion"` results banner is pushed straight from the
  # synchronous reply here — no PubSub round-trip needed for the
  # caller's own session, unlike the former lord's own
  # `"game:rebellion_declared"` notification (`handle_info/2` below).
  defp do_confirm_declare_independence(socket, lord_user_id) do
    %{world: world, user: user} = socket.assigns

    case Game.declare_independence(world, user, lord_user_id) do
      {:ok, %{message: message}} ->
        socket =
          socket
          |> assign(declare_independence_lord_user_id: nil, independence_preview: nil)
          |> refresh_vassalage()
          |> refresh_rebellions()
          |> refresh_board()
          |> push_event("game:rebellion", %{message: message})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # QA issue bd93cc0a: shared post-action refresh for a production/
  # defend steward command — `refresh_board/1` alone (the "steward_
  # collect_bank" baseline) is no longer enough once `@vassal.steward`/
  # `@alliance.steward` carries live per-city catalogs and per-unit
  # `adjacent_tile_ids`: a stale row after a successful defend order
  # would keep offering a tile that's no longer actually adjacent to
  # the unit's NEW position, and clicking it would misfire as provable
  # sabotage against an innocent steward's own Honor. `refresh_vassalage/1`
  # keeps `@vassals` current for the lord/fellow-vassal path;
  # `AlliancePanel` owns its own `@alliances` assign, so its refresh
  # goes through the same `send_update/2` forward `handle_info(:alliances_changed, _)`
  # already uses.
  defp refresh_after_steward_action(socket) do
    send_update(BrokenOathsWeb.GameLive.AlliancePanel, id: "alliance-panel", refresh: true)

    socket
    |> refresh_board()
    |> refresh_vassalage()
  end

  # -------------------------------------------------------------------
  # City loop helpers
  # -------------------------------------------------------------------

  # Shared unit-panel selection (the `select_unit` cycle and its by-id
  # fallthrough both land here): open the unit side panel and clear every
  # other panel, exactly as the handler did inline before the cycle was
  # widened to include cities.
  defp apply_unit_panel(socket, unit, selected_unit_id) do
    socket
    |> assign(
      selected_unit_id: selected_unit_id,
      selected_unit: unit,
      selected_order: unit && unit.order,
      allowed_improvements:
        PlayView.worker_allowed_improvements(
          socket.assigns.world,
          unit,
          socket.assigns.player_research
        ),
      current_dig: PlayView.worker_current_dig(socket.assigns.improvements, unit),
      attackable_cities:
        PlayView.attackable_cities(socket.assigns.world, unit, socket.assigns.enemy_cities),
      shoot_targets:
        PlayView.shoot_targets(
          socket.assigns.world,
          unit,
          socket.assigns.units,
          socket.assigns.camps,
          socket.assigns.enemy_cities
        ),
      order_error: nil,
      improvement_error: nil,
      selected_city_id: nil,
      selected_city: nil,
      selected_tile: nil,
      selected_camp_id: nil,
      selected_camp: nil
    )
    |> push_event("game:selected", %{unit_id: selected_unit_id})
    |> push_selected_path()
    |> push_city_selection()
  end

  # City-panel selection reached by CYCLING off a unit stacked on the city
  # (QA issue adc8c79e); mirrors the `select_city` handler's own assigns,
  # plus a `selected_order` clear since we're arriving from a unit.
  defp apply_city_panel(socket, city) do
    socket
    |> assign(
      selected_city_id: city.id,
      selected_city: city,
      assignable_tiles: PlayView.assignable_tiles(socket.assigns.world, city),
      copper_access?: Game.copper_access?(socket.assigns.world, socket.assigns.user),
      coastal?: PlayView.coastal?(socket.assigns.world, city),
      city_error: nil,
      selected_unit_id: nil,
      selected_unit: nil,
      selected_order: nil,
      selected_tile: nil,
      attackable_cities: [],
      shoot_targets: [],
      selected_camp_id: nil,
      selected_camp: nil
    )
    |> push_city_selection()
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-64px)] select-none [-webkit-touch-callout:none]">
      <Layouts.flash_group flash={@flash} />

      <div class="flex items-center gap-3 px-4 py-2 bg-base-200 border-b border-base-300 flex-nowrap overflow-x-auto md:flex-wrap md:overflow-visible">
        <.live_component
          module={BrokenOathsWeb.GameLive.TurnBar}
          id="turn-bar"
          turn={@turn}
          turn_ends_at={@turn_ends_at}
        />

        <span class="badge badge-neutral gap-1" data-test="player-gold">
          <.icon name="hero-circle-stack" class="w-3 h-3" /> {@gold}
        </span>

        <%!-- Stories 909/910: Bank/Honor/steward-log — gated on
             `@feudal_enabled?` (`Game.feudal_enabled?/0`), unlike
             `vassals-list`/`vassal-status` below (naturally empty with
             the flag off since nothing ever creates the relationship
             data that powers them). These three read STRUCTURAL
             `Player` fields that exist — at inert defaults — on every
             player regardless of the flag, so without an explicit gate
             here prod's own board would show a "0/100" bank badge and a
             "100" Honor badge today, well before this batch is meant to
             be user-facing (`BrokenOathsWeb.GameLive.FeudalFlagTest`'s
             own "with the flag OFF" case asserts none of the three ever
             render). --%>
        <FeudalTopBar.panel
          feudal_enabled?={@feudal_enabled?}
          bank={@bank}
          bank_error={@bank_error}
          honor={@honor}
          steward_log={@steward_log}
          vassals={@vassals}
          known_players={@known_players}
          conspiracy_heat={@conspiracy_heat}
          pact_informed={@pact_informed}
          rebellions_as_lord={@rebellions_as_lord}
          user={@user}
          captured_cities={@captured_cities}
          vassal_status={@vassal_status}
          declare_independence_lord_user_id={@declare_independence_lord_user_id}
          independence_preview={@independence_preview}
          rebellion_status={@rebellion_status}
          pact={@pact}
          pact_panel_open?={@pact_panel_open?}
          pact_candidates={@pact_candidates}
        />

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

      <Modals.abandon_confirm confirm_abandon?={@confirm_abandon?} />

      <Modals.oath_screen vassal_status={@vassal_status} />

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

        <BoardOverlays.overlays
          chat_open={@chat_open}
          known_players={@known_players}
          world={@world}
          user={@user}
          chat_target_user_id={@chat_target_user_id}
          order_error={@order_error}
          combat_error={@combat_error}
          city_error={@city_error}
          improvement_error={@improvement_error}
          steward_error={@steward_error}
          player_research={@player_research}
          cities={@cities}
          player_stats={@player_stats}
          gold_per_turn={@gold_per_turn}
          selected_tile={@selected_tile}
          selected_camp={@selected_camp}
          selected_unit={@selected_unit}
          selected_order={@selected_order}
          allowed_improvements={@allowed_improvements}
          current_dig={@current_dig}
          attackable_cities={@attackable_cities}
          shoot_targets={@shoot_targets}
          selected_city={@selected_city}
          assignable_tiles={@assignable_tiles}
          copper_access?={@copper_access?}
          coastal?={@coastal?}
        />
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
            this.drawScheduled = false
            this.lowDetail = false
            this.settleTimer = null
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
              // QA issue d80792c6 — a touch long-press must never win
              // the race against the browser's own text-selection/
              // callout gesture; `select-none`/`[-webkit-touch-callout:
              // none]` on Play's own root (see `render/1`) cover the
              // visual side, this stops the native gesture at its
              // source. Desktop mouse/pen input is untouched.
              if (e.pointerType === "touch") e.preventDefault()

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
                this.interact(true)
                return
              }

              const dx = e.clientX - this.last.x
              const dy = e.clientY - this.last.y
              if (!this.moved && Math.abs(dx) + Math.abs(dy) < 4) return
              this.moved = true
              clearTimeout(this.lpTimer)
              this.last = {x: e.clientX, y: e.clientY}
              panBy(dx, dy)
              this.interact(e.pointerType === "touch")
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
              this.interact(false)
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
          //
          // QA issue d403faa6: a stacked tile (a non-combat unit
          // escorted by a combat unit, both this player's own) can no
          // longer be resolved to "the unit" client-side — `tile_id`
          // rides along with this best-guess `unit_id` so the server's
          // own `owned_stack_on_tile/3` + `next_unit_in_stack/2` can
          // cycle through the player's own stack there instead.
          click(e) {
            const tile = this.hitTile(e)
            if (tile == null) return

            const unit = this.units.find((u) => u.tile_id === tile)
            if (unit) { this.pushEvent("select_unit", {unit_id: unit.id, tile_id: tile}); return }

            // QA issue 56ee521a — a hostile (enemy) city never opens
            // `CityPanel` (that component assumes an OWNED city's own
            // shape: queue, worked tiles, etc., which `city_marker/1`'s
            // trimmed board payload doesn't carry for someone else's
            // city) — falls through to the plain tile-info panel below,
            // same as clicking any other occupied-but-foreign ground.
            const city = this.cities.find((c) => c.tile_id === tile && !c.hostile)
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

            // A right click on an adjacent barbarian, camp, or an INTACT
            // hostile player city is an attack order, not a move — the
            // RTS convention (story 891/894, QA issue 56ee521a for the
            // city case). A BROKEN hostile city (0 HP, not yet captured —
            // `city.broken`, QA issue 7f91cff2) is the one exception: the
            // capture itself is a MOVEMENT event ("Civ-style — you commit
            // and hold a body," `Siege.materialize_captures/2`), so this
            // deliberately falls through to the plain move order below
            // instead of re-issuing a harmless, floor-clamped attack.
            // Anything else falls through to movement too.
            const tile = this.hitTile(e)
            if (tile != null) {
              const enemy = this.units.find((u) => u.tile_id === tile && u.type === "barbarian_warrior")
              if (enemy) { this.pushEvent("attack", {unit_id: this.selectedId, target_unit_id: enemy.id}); return }
              const camp = this.camps.find((c) => c.tile_id === tile)
              if (camp) { this.pushEvent("attack", {unit_id: this.selectedId, target_camp_id: camp.id}); return }
              const hostileCity = this.cities.find((c) => c.tile_id === tile && c.hostile)
              if (hostileCity && !hostileCity.broken) {
                this.pushEvent("attack", {unit_id: this.selectedId, target_city_id: hostileCity.id})
                return
              }
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
              this.render()
              const pulsing = this.units.some((u) => u.order && u.order.status === "pending")
              const flashing = this.combatFlash && now < this.combatFlash.until
              if (this.anims.size || pulsing || flashing) this.raf = requestAnimationFrame(step)
            }
            this.raf = requestAnimationFrame(step)
          },

          // Coalesce redraws to one per animation frame. Many LiveView
          // pushes (a turn tick fans out window+units+cities+visibility+…)
          // and every pointermove used to each force a full synchronous
          // render(); on mobile that stacked several whole-board renders
          // into a single frame. They now collapse into one rAF-driven
          // render() (issue 6f5e665b — bad mobile performance).
          draw() {
            if (this.drawScheduled) return
            this.drawScheduled = true
            requestAnimationFrame(() => { this.drawScheduled = false; this.render() })
          },

          // While the camera is actively moving, optionally fall back to a
          // cheaper frame — flat terrain fills instead of the per-tile pattern
          // setTransform, no hairline grid stroke, no cloud shells. This is
          // gated by the CALLER on input type: TOUCH gestures (mobile pinch/
          // drag) pass true — the pattern fills genuinely janked there (issue
          // 6f5e665b) — while a MOUSE pan or wheel zoom on desktop passes
          // false and always keeps the full texture, so the terrain never
          // "flashes to flat color" mid-drag (issue 4ed25499 + follow-up).
          // Settling ~140ms after the gesture restores full detail either way.
          interact(lowDetail) {
            this.lowDetail = lowDetail
            clearTimeout(this.settleTimer)
            this.settleTimer = setTimeout(() => { this.lowDetail = false; this.render() }, 140)
            this.draw()
          },

          render() {
            const ctx = this.ctx
            if (!ctx) return
            const GR = window.GlobeRender
            const dpr = this.dpr || 1
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
            ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
            // QA issue 551f9a55 — nearest-neighbor for the WHOLE frame,
            // not just decor onward as before: the terrain pattern fill
            // below is the one layer that used to render with the
            // canvas default (bilinear) smoothing, which is exactly
            // what made it shimmer/ripple as `patternPool.for`'s own
            // zoom-anchored offset drifts by sub-pixel amounts every
            // frame during a pan. Also matches the pixel-art sprites/
            // decor this game already renders with it below.
            ctx.imageSmoothingEnabled = false

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
              // Motion frames skip the zoom-anchored pattern setTransform
              // + fill (the single hottest per-tile cost) for a flat
              // palette color; the settle frame restores the texture.
              ctx.fillStyle = this.lowDetail ? color : (this.patterns.for(ctx, row[3], this.scale, cx, cy) || color)
              ctx.fill()

              // Explored-but-out-of-vision: remembered terrain under a
              // thin wash of the fog tone (distinct from full shroud)
              if (!this.visibleSet.has(id)) {
                ctx.fillStyle = "rgba(168,172,181,0.45)"
                ctx.fill()
              }

              // QA issue 46047ea6 — a faint per-tile edge so the hex
              // grid itself reads at a glance, not just wherever terrain
              // colors happen to differ. Deliberately every tile's OWN
              // polygon, not `GlobeRender.computeBorderEdges` (that only
              // traces the OUTER perimeter of a group — right below, for
              // the selected city's territory outline); interior hex
              // seams need to show too, and a shared edge simply gets
              // stroked twice, once from each side, at the same spot.
              // Reuses the SAME open path `ctx.fill()` already traced
              // above — free to stroke. Kept subtle (low alpha, hairline
              // width): legible grid, not a busy overlay.
              if (!this.lowDetail) {
                ctx.strokeStyle = "rgba(10, 12, 18, 0.16)"
                ctx.lineWidth = 1
                ctx.stroke()
              }
            }

            // Terrain decor billboards (mountains, hills, tree cover) at
            // projected tile centers, back-to-front, dimmed on remembered
            // tiles. Skipped entirely below readability size. (Already
            // nearest-neighbor from the top of `draw()` — see above.)
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

            // Improvement billboards (farms, mines, roads): built ON the
            // terrain like decor, below cities/units. Pillaged ones
            // render half-faded — visibly wrecked, visibly repairable.
            // QA issue 5656770d — a tile can now carry BOTH a yield
            // improvement (farm/mine/pasture) AND a road at once; a
            // `:road` billboard renders smaller and nudged toward one
            // corner of the tile so it never fully hides whatever's
            // centered there, the same "both queryable, both visible"
            // fix as the server-side data model.
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
                if (imp.kind === "road") {
                  const roadSize = impSize * 0.55
                  GR.drawBillboard(ctx, img, px + roadSize * 0.5, py + roadSize * 0.4, roadSize)
                } else {
                  GR.drawBillboard(ctx, img, px, py, impSize)
                }
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

                // QA issue 56ee521a — a thin red ring marks a hostile
                // (enemy, attackable) city, whether or not the real
                // sprite loaded yet, so a player can tell "mine" from
                // "attack target" at a glance.
                if (c.hostile) {
                  ctx.beginPath()
                  ctx.arc(px, py, citySize * 0.32, 0, 2 * Math.PI)
                  ctx.strokeStyle = "#dc2626"
                  ctx.lineWidth = 2
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
            if (!this.lowDetail) {
              for (const {row} of order) {
                const lvl = this.airspace[row[0]]
                if (!lvl) continue
                ctx.beginPath()
                GR.tracePolygon(ctx, R, row, 7, GR.CLOUD_ALT)
                ctx.fillStyle = this.CLOUD[lvl]
                ctx.fill()
              }
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
end
