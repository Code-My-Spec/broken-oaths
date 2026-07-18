defmodule BrokenOathsSpex.SharedGivens do
  @moduledoc """
  Shared `given_ :atom` steps for BDD specs. Import with a plain
  `import BrokenOathsSpex.SharedGivens` in a spex module.
  """

  use SexySpex.Givens

  # `:two_players_discovered_each_other` below drives a real LiveView
  # and uses `assert_push_event/4` (a macro that expands to
  # `assert_receive/2`) — `SexySpex.Givens` doesn't pull in
  # `ExUnit.Assertions`, `Phoenix.ConnTest`/`Phoenix.LiveViewTest`, or
  # the `@endpoint` attribute those two need, the way an
  # `ExUnit.Case`/`BrokenOathsSpex.Case`-based module does, so all of
  # that is set up explicitly here.
  @endpoint BrokenOathsWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BrokenOathsSpex.Fixtures

  # A confirmed player logged in on `context.conn` (`context.user`).
  register_given :registered_player, context do
    user = Fixtures.user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> BrokenOathsTest.ConnCase.log_in_user(user)

    {:ok, context |> Map.put(:user, user) |> Map.put(:conn, conn)}
  end

  # A second player with their own session (`context.other_user` /
  # `context.other_conn`) — for multiplayer scenarios.
  register_given :second_registered_player, context do
    user = Fixtures.user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> BrokenOathsTest.ConnCase.log_in_user(user)

    {:ok, context |> Map.put(:other_user, user) |> Map.put(:other_conn, conn)}
  end

  # A third player with their own session (`context.third_user` /
  # `context.third_conn`) — for scenarios needing several civilizations
  # at once (e.g. surrounding a single city with blockers).
  register_given :third_registered_player, context do
    user = Fixtures.user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> BrokenOathsTest.ConnCase.log_in_user(user)

    {:ok, context |> Map.put(:third_user, user) |> Map.put(:third_conn, conn)}
  end

  # A deterministic world (`context.world`) — fixture frequency, seed 424242.
  register_given :a_world, context do
    {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 424_242}))}
  end

  # `context.user`'s freshly founded, size-1 city in `context.world`
  # (`context.play_live`, `context.city`) — the common starting point
  # for story 902's research specs (and any other story that just needs
  # a bare city with no further setup): joins the world, mounts
  # `GameLive.Play`, and founds a city with the player's starting
  # settler. Requires `context.world` and `context.user`/`context.conn`
  # — run `:a_world` and `:registered_player` first.
  register_given :a_founded_city, context do
    {:ok, join_live, _html} = live(context.conn, "/play")

    join_live
    |> element("[data-test='join-world-#{context.world.id}']")
    |> render_click()

    {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

    [settler | _] =
      for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

    render_hook(play_live, "found_city", %{"unit_id" => settler.id})
    [city] = Fixtures.player_cities(context.world, context.user)

    {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
  end

  # Two players who have discovered each other in `context.world`:
  # `context.user`'s civilization has seen `context.other_user`'s (and
  # vice versa — discovery is mutual, story 899). Both join the world,
  # then this player's lord scouts toward the other player's unit until
  # it enters vision — the exact first-contact trigger
  # `BrokenOaths.Game.Discovery` (story 899) watches for, and the
  # precondition every chat criterion (story 900) unlocks on. Mirrors
  # the scout-until-visible idiom already used by story 876's
  # fog-of-war specs (see `criterion_7434_a_stranger_in_remembered_
  # territory_is_invisible_spex.exs`).
  #
  # Requires `context.world`, `context.user`/`context.conn`, and
  # `context.other_user`/`context.other_conn` — run `:a_world`,
  # `:registered_player`, and `:second_registered_player` first.
  register_given :two_players_discovered_each_other, context do
    for conn <- [context.conn, context.other_conn] do
      {:ok, join_live, _html} = live(conn, "/play")

      join_live
      |> element("[data-test='join-world-#{context.world.id}']")
      |> render_click()
    end

    {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

    [lord | _] =
      for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

    [stranger | _] = Fixtures.player_units(context.world, context.other_user)

    render_hook(play_live, "queue_move", %{
      "unit_id" => lord.id,
      "to_tile" => stranger.tile_id
    })

    seen? =
      Enum.reduce_while(1..30, false, fn _, _ ->
        Fixtures.advance_turn(context.world)

        assert_push_event(play_live, "game:units", %{units: units}, 1000)

        if Enum.any?(units, &(&1.id == stranger.id)),
          do: {:halt, true},
          else: {:cont, false}
      end)

    assert seen?, "the lord never scouted within sight of the other player's unit"

    {:ok, context}
  end

  # A player who has founded a first city and advanced to the Bronze
  # Age (story 903) by selecting Bronze Working as their research and
  # letting enough turns pass for its 100-science cost to bank in full.
  #
  # Real surface — story 902's `TechPanel`/`GameLive.Play` own the
  # research-selection event contract this given drives:
  # `"toggle_tech_panel"` opens the panel, `"select_research"` with
  # `%{"tech" => "bronze_working"}` raises the `bronze-working-warning`
  # confirm (`Play`'s own `select_research`/`bronze_working_pending?`
  # handler — see `BrokenOathsWeb.GameLive.TechPanel`'s moduledoc for
  # the full flow), and `"bronze_working_confirm"` is what actually
  # calls `Game.set_research(world, user, :bronze_working)`. Story 903's
  # own specs (this given's callers) drive the SAME event names story
  # 902's specs already do — one consistent `TechPanel` contract for
  # both stories, not two.
  #
  # `context.research_select_result` is kept as `:ok` for every caller
  # that still asserts on it (`context.research_select_result == :ok`)
  # — selecting Bronze Working through the real flow no longer crashes
  # the LiveView, so this is now a genuine confirmation rather than a
  # tolerated-crash placeholder.
  #
  # Turn math: Bronze Working costs 100 science (`Research.cost/1`,
  # stone_age.md §6.1). A lone size-1 city already earns 2/turn
  # (`Research.science_per_turn/1`, `2 * size`), so 50 turns already
  # covers it even with zero growth; growth (an independent mechanic)
  # only ever raises that rate further. 60 is a safe, generous
  # overshoot, in the same scale existing specs already accept for long
  # waits (e.g. `criterion_7477`'s 300-turn bound).
  #
  # Requires `context.world`, `context.user`/`context.conn` — run
  # `:a_world` and `:registered_player` first.
  register_given :player_reached_bronze_age, context do
    {:ok, context} = a_founded_city(context)

    render_hook(context.play_live, "toggle_tech_panel", %{})
    render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
    render_hook(context.play_live, "bronze_working_confirm", %{})

    for _ <- 1..60, do: Fixtures.advance_turn(context.world)

    {:ok, Map.put(context, :research_select_result, :ok)}
  end

  # Trap-exit-guarded `render_hook/3` — generic version of
  # `BrokenOathsSpex.Story891.Criterion7537Spex`'s `attempt_attack/3`.
  # See that module's own doc for the full rationale. Returns `:ok` if
  # `event` was handled without crashing the view, `:crashed` if
  # calling it took the LiveView process down (no matching
  # `handle_event` clause exists for `event` yet).
  def attempt_event(live_view, event, params) do
    original_trap = Process.flag(:trap_exit, true)

    result =
      try do
        render_hook(live_view, event, params)
        :ok
      rescue
        _ -> :crashed
      catch
        :exit, _ -> :crashed
      end

    result =
      receive do
        {:EXIT, _pid, _reason} -> :crashed
      after
        100 -> result
      end

    Process.flag(:trap_exit, original_trap)
    result
  end

  # -------------------------------------------------------------------
  # Feudal batch helpers (stories 906-910): a besieger and a besieged,
  # both real players, both driven exclusively through their own
  # `GameLive.Play` mount — see each calling criterion's own moduledoc
  # for the specific judgment calls these compose into.
  # -------------------------------------------------------------------

  @doc """
  Joins both `context.user` (the eventual attacker) and
  `context.other_user` (the eventual defender) to `context.world`, then
  has `context.other_user` found a single city with their starting
  settler. Returns `context` extended with `:play_live` (the attacker's
  own mounted `GameLive.Play`), `:other_play_live` (the defender's),
  and `:other_city` (the defender's freshly founded city).

  Requires `:a_world`, `:registered_player`, `:second_registered_player`
  already run.
  """
  def join_and_found_rival_city(context) do
    {:ok, join_live, _html} = live(context.conn, "/play")

    join_live
    |> element("[data-test='join-world-#{context.world.id}']")
    |> render_click()

    {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

    {:ok, other_join_live, _html} = live(context.other_conn, "/play")

    other_join_live
    |> element("[data-test='join-world-#{context.world.id}']")
    |> render_click()

    {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

    [other_settler | _] =
      for u <- Fixtures.player_units(context.world, context.other_user),
          u.type == :settler,
          do: u

    render_hook(other_play_live, "found_city", %{"unit_id" => to_string(other_settler.id)})
    [other_city] = Fixtures.player_cities(context.world, context.other_user)

    context
    |> Map.put(:play_live, play_live)
    |> Map.put(:other_play_live, other_play_live)
    |> Map.put(:other_city, other_city)
  end

  @doc """
  Destroys every wilderness camp (and every unit tied to one) in
  `world` — a thin, self-documenting wrapper around
  `Fixtures.isolate_camp/2`'s own "keep only this one camp" contract,
  called with an id that can never match a real camp so EVERY camp is
  torn down. Story 892 seeds wilderness camps the moment either
  player's FIRST city is founded, and story 893 gives those camps a
  real roam/attack AI — a besieging unit or a long-growing rival city
  in this feudal batch's own specs is routinely exposed to dozens of
  turns near BOTH players' camp rings, and an independently-roaming
  barbarian killing the tracked attacker (or pillaging the tracked
  defender) mid-scenario would fail the spec for a reason that has
  nothing to do with the siege criterion under test — the same
  interference story 895's own `criterion_7567`/`criterion_7566`
  already guard against with `Fixtures.isolate_camp/2`, generalized
  here to "no camps at all" since THIS batch's scenarios have two
  independent camp rings (one per player) to worry about, not one.
  Call this once, right after every city this scenario's `given_`
  founds is already founded (founding is what seeds new camps) and
  before any turn-advancing march or siege begins.
  """
  def clear_all_camps(world), do: Fixtures.isolate_camp(world, -1)

  @doc """
  Marches `unit` (owned by `user`, driven through `user`'s own
  `play_live`) to `to_tile` via the real `"queue_move"` hook, advancing
  real turn boundaries (`Fixtures.advance_turn/1`) up to `max_turns`
  times until it arrives, then tops its movement back up to max via
  `Fixtures.recharge_unit/2` — the same march-then-recharge idiom
  `criterion_7567`'s (story 895) own long march already established:
  the march's own final step spends the mover's movement in the same
  tick it arrives, which would otherwise refuse an immediate follow-up
  action (an attack, or a further move) this same test session. Returns
  the freshest copy of `unit` — arrived at `to_tile`, or wherever it
  actually got to within `max_turns` (a blocked destination, e.g. a
  still-garrisoned enemy city, never arrives — callers that expect that
  are responsible for asserting on the returned `tile_id` themselves,
  not this helper).
  """
  def march_to(play_live, world, user, unit, to_tile, max_turns \\ 40) do
    render_hook(play_live, "queue_move", %{
      "unit_id" => to_string(unit.id),
      "to_tile" => to_tile
    })

    Enum.reduce_while(1..max_turns, :ok, fn _, :ok ->
      [u] = for x <- Fixtures.player_units(world, user), x.id == unit.id, do: x

      if u.tile_id == to_tile do
        {:halt, :ok}
      else
        Fixtures.advance_turn(world)
        {:cont, :ok}
      end
    end)

    :ok = Fixtures.recharge_unit(world, unit.id)
    [refreshed] = for x <- Fixtures.player_units(world, user), x.id == unit.id, do: x
    refreshed
  end

  @doc """
  Finds a `:land` tile adjacent to `target_tile_id` that isn't already
  occupied by one of `exclude_tiles` (the mover's own starting tiles,
  typically) — the same "first free adjacent land tile" idiom every
  combat spec since story 891 already repeats inline
  (`criterion_7533`/`criterion_7567` and friends), lifted here once for
  the feudal batch's own repeated need to land an attacker next door to
  a rival's city.
  """
  def adjacent_land_tile(world, target_tile_id, exclude_tiles \\ []) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end

    [tile | _] =
      world
      |> Fixtures.adjacent_tiles(target_tile_id)
      |> Enum.filter(land?)
      |> Enum.reject(&(&1 in exclude_tiles))

    tile
  end

  @doc """
  Repeatedly orders `attacker` (`user`'s own unit, already standing
  adjacent to `city.tile_id`) to assault `city` through the real
  `"attack"` hook (`target_city_id`), advancing a real turn boundary
  between every swing — a boundary refills movement for every unit
  (`Turn.tick/1`'s own `movement: unit.max_movement` reset), so no
  `Fixtures.recharge_unit/2` is needed between repeated attacks the way
  `march_to/5` needs it after a march. Stops early once the defending
  player's own read of the city shows `hp <= 0`, or after `max_attacks`
  swings (a generous safety cap, not a tuned number — see the calling
  criterion's own moduledoc for whether zero HP is actually reached
  under today's code). Every boundary this loop advances ALSO runs the
  city's own `Game.CityDefense.regen/1` phase (5 HP), since an attack
  landed through the immediate, out-of-tick "attack" surface never
  suppresses the tick's own regen (see `CityDefense`'s own "Regeneration"
  doc) — net progress per round is a swing's damage MINUS 5, not the
  swing's raw damage, so `max_attacks` needs real headroom over a naive
  "100 HP / average swing damage" estimate. Returns the freshest city
  row.
  """
  def grind_city(attacker_play_live, world, attacker, defender_user, city, max_attacks \\ 40) do
    Enum.reduce_while(1..max_attacks, city, fn _, current_city ->
      if current_city.hp <= 0 do
        {:halt, current_city}
      else
        attempt_event(attacker_play_live, "attack", %{
          "unit_id" => to_string(attacker.id),
          "target_city_id" => to_string(current_city.id)
        })

        Fixtures.advance_turn(world)

        [refreshed] =
          for c <- Fixtures.player_cities(world, defender_user), c.id == current_city.id, do: c

        {:cont, refreshed}
      end
    end)
  end

  @doc """
  The full 906 capture sequence, composed from `grind_city/6` and
  `march_to/6`: assaults `city` (already-adjacent `attacker`, owned by
  `user`, driven through `attacker_play_live`) down across real turn
  boundaries, then walks `attacker` onto the city's own tile — "you
  commit and hold a body"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`). Returns
  `{attacker, broken_city}`: the freshest copy of `attacker` (wherever
  it actually ended up — see `march_to/6`'s own doc, entry may still be
  refused today if `city` is garrisoned) and the freshest city row
  `grind_city/6` last saw. Callers needing a garrisoned "fallen
  garrison" scenario should NOT use this against an already-garrisoned
  city — see `BrokenOathsSpex.Story906.Criterion7661Spex`'s own
  moduledoc for why (real counter-fire would kill the besieger over
  many rounds); garrison AFTER calling this instead.
  """
  def capture_city(attacker_play_live, world, user, attacker, defender_user, city) do
    broken_city = grind_city(attacker_play_live, world, attacker, defender_user, city)
    attacker = march_to(attacker_play_live, world, user, attacker, city.tile_id)
    {attacker, broken_city}
  end

  @doc """
  Composes `join_and_found_rival_city/1` + `clear_all_camps/1` +
  `capture_city/6` into the single-city subjugation `given_` every
  story 908 (tribute) spec needs as its own precondition: `context.
  other_user` founds their ONE city, `context.user`'s Lord marches
  adjacent and grinds/walks it down — the same flow
  `BrokenOathsSpex.Story907.Criterion7666Spex` already drives inline.
  Returns `context` extended with `:play_live`/`:other_play_live`/
  `:other_city` (from `join_and_found_rival_city/1`) and `:my_lord`
  (the besieger, wherever it actually ended up — see `capture_city/6`'s
  own doc).
  """
  def a_freshly_subjugated_vassal(context) do
    context = join_and_found_rival_city(context)
    :ok = clear_all_camps(context.world)

    [my_lord] =
      for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

    target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
    my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

    {my_lord, _broken_city} =
      capture_city(
        context.play_live,
        context.world,
        context.user,
        my_lord,
        context.other_user,
        context.other_city
      )

    Map.put(context, :my_lord, my_lord)
  end

  @doc """
  Cleanly terminates `play_live`'s own LiveView process and waits for
  its DOWN — story 909's own "offline" signal. No Presence/online
  tracking exists anywhere in this codebase yet (`BrokenOaths.Game.
  Bank`, this story's own component, doesn't exist either), but a
  disconnected LiveView socket IS structurally what "the player went
  offline" means for a Phoenix app — the real, literal surface a future
  Presence-based implementation would key off. Never mounting a
  `GameLive.Play` for a player at all is equally "offline"; this helper
  is for a scenario that needs them to have BEEN online first (e.g. to
  found a city) and then go offline for the turns that follow.
  """
  def go_offline(play_live) do
    ref = Process.monitor(play_live.pid)
    swallow_exit(fn -> GenServer.stop(play_live.pid) end)

    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> :ok
    after
      1000 -> :ok
    end
  end

  defp swallow_exit(fun) do
    fun.()
  catch
    :exit, _ -> :ok
  end

  @doc """
  General form of `a_freshly_subjugated_vassal/1`: subjugates
  `vassal_user` (driven through `vassal_conn`) under `lord_user`/
  `lord_conn`, both already registered users (their conns need not have
  joined `world` yet — this joins both, idempotently for a lord who's
  already a member from a PRIOR call, the same "join-world still works
  for an existing member" fact `BrokenOathsSpex.Story908.
  Criterion7679Spex` already relies on). Unlike `a_freshly_subjugated_
  vassal/1`, this never touches any `context.user`/`context.other_user`-
  shaped key, so a scenario needing SEVERAL vassals under the same lord
  (story 910's own "fellow vassal" criteria) can call this once per
  vassal without one call's own `other_user`/`other_city` clobbering
  the last. Returns `%{lord_play_live:, vassal_play_live:, vassal_city:,
  lord_unit:}` (`lord_unit` wherever it actually ended up — see
  `capture_city/6`'s own doc).
  """
  def subjugate(world, lord_conn, lord_user, vassal_conn, vassal_user) do
    {:ok, lord_join_live, _html} = live(lord_conn, "/play")

    lord_join_live
    |> element("[data-test='join-world-#{world.id}']")
    |> render_click()

    {:ok, lord_play_live, _html} = live(lord_conn, "/play/#{world.id}")

    {:ok, vassal_join_live, _html} = live(vassal_conn, "/play")

    vassal_join_live
    |> element("[data-test='join-world-#{world.id}']")
    |> render_click()

    {:ok, vassal_play_live, _html} = live(vassal_conn, "/play/#{world.id}")

    [vassal_settler | _] =
      for u <- Fixtures.player_units(world, vassal_user), u.type == :settler, do: u

    render_hook(vassal_play_live, "found_city", %{"unit_id" => to_string(vassal_settler.id)})
    [vassal_city] = Fixtures.player_cities(world, vassal_user)

    :ok = clear_all_camps(world)

    [lord_unit] = for u <- Fixtures.player_units(world, lord_user), u.type == :lord, do: u
    target = adjacent_land_tile(world, vassal_city.tile_id, [lord_unit.tile_id])
    lord_unit = march_to(lord_play_live, world, lord_user, lord_unit, target)

    {lord_unit, _broken_city} =
      capture_city(lord_play_live, world, lord_user, lord_unit, vassal_user, vassal_city)

    %{
      lord_play_live: lord_play_live,
      vassal_play_live: vassal_play_live,
      vassal_city: vassal_city,
      lord_unit: lord_unit
    }
  end

  @doc """
  Joins both `user_a`/`conn_a` and `user_b`/`conn_b` to `world`, scouts
  them into mutual discovery (story 899, the same real precondition
  `GameLive.AlliancePanel`'s own `known_players` roster requires), then
  drives the REAL propose/accept alliance flow this codebase already
  ships (`BrokenOaths.Game.propose_alliance/3`/`accept_alliance/3`,
  story 901, wired to `GameLive.AlliancePanel`'s own `"propose_alliance"`/
  `"accept_alliance"` events) — unlike every other not-yet-implemented
  seam elsewhere in this feudal batch, alliance itself is REAL, already-
  shipped functionality; only STEWARDING an ally (story 910's own new
  ground) is what's missing. Returns `%{play_live_a:, play_live_b:}`,
  both fresh, freshly re-mounted post-acceptance so their own `alliances`
  assign is current.
  """
  def establish_accepted_alliance(world, conn_a, user_a, conn_b, user_b) do
    for conn <- [conn_a, conn_b] do
      {:ok, join_live, _html} = live(conn, "/play")

      join_live
      |> element("[data-test='join-world-#{world.id}']")
      |> render_click()
    end

    {:ok, play_live_a, _html} = live(conn_a, "/play/#{world.id}")

    [lord_a | _] = for u <- Fixtures.player_units(world, user_a), u.type == :lord, do: u
    [unit_b | _] = Fixtures.player_units(world, user_b)

    render_hook(play_live_a, "queue_move", %{
      "unit_id" => to_string(lord_a.id),
      "to_tile" => unit_b.tile_id
    })

    seen? =
      Enum.reduce_while(1..60, false, fn _, _ ->
        Fixtures.advance_turn(world)
        assert_push_event(play_live_a, "game:units", %{units: units}, 1000)

        if Enum.any?(units, &(&1.id == unit_b.id)), do: {:halt, true}, else: {:cont, false}
      end)

    assert seen?, "player A's lord never scouted within sight of player B's unit"

    {:ok, play_live_a, _html} = live(conn_a, "/play/#{world.id}")
    {:ok, play_live_b, _html} = live(conn_b, "/play/#{world.id}")

    play_live_a
    |> element("[data-test='alliance-button']")
    |> render_click()

    play_live_a
    |> element("[data-test='ally-candidate-#{user_b.id}'] [data-test='propose-alliance']")
    |> render_click()

    play_live_b
    |> element("[data-test='alliance-button']")
    |> render_click()

    play_live_b
    |> element("[data-test='alliance-panel'] [data-test='accept-alliance']")
    |> render_click()

    {:ok, play_live_a, _html} = live(conn_a, "/play/#{world.id}")
    {:ok, play_live_b, _html} = live(conn_b, "/play/#{world.id}")

    %{play_live_a: play_live_a, play_live_b: play_live_b}
  end
end
