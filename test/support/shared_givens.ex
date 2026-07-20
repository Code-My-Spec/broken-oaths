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
  # `BrokenOaths.Diplomacy.Discovery` (story 899) watches for, and the
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
  # Age (story 903) by researching Mining (its now-required
  # prerequisite — story 902 EXPANDED the tree per playtest issue
  # 133b4893 so Bronze Working can no longer be picked directly),
  # then selecting Bronze Working as their research and letting enough
  # turns pass for its 100-science cost to bank in full.
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
  # Turn math: Mining costs 75 science and Bronze Working costs 100
  # (`Research.cost/1`) — 175 total, plus Mining must fully complete
  # before Bronze Working is even selectable
  # (`Research.prereqs_met?/2`). Mining is researched to completion
  # first via a convergence loop (bounded at 60 turns, the same pattern
  # `criterion_7628`'s own Mining wait uses) rather than a fixed turn
  # count, since exactly how many turns Mining needs depends on the
  # city's own growth curve. Bronze Working then gets its own 60-turn
  # generous overshoot exactly as before — a lone size-1 city already
  # earns 2/turn (`Research.science_per_turn/1`), so 50 turns already
  # covers its 100 cost even with zero further growth.
  #
  # Requires `context.world`, `context.user`/`context.conn` — run
  # `:a_world` and `:registered_player` first.
  register_given :player_reached_bronze_age, context do
    {:ok, context} = a_founded_city(context)

    render_hook(context.play_live, "toggle_tech_panel", %{})
    render_hook(context.play_live, "select_research", %{"tech" => "mining"})

    Enum.reduce_while(1..60, :ok, fn _, :ok ->
      if has_element?(context.play_live, "[data-test='tech-completed-mining']") do
        {:halt, :ok}
      else
        Fixtures.advance_turn(context.world)
        {:cont, :ok}
      end
    end)

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

  `max_turns` (default 40, same as `march_to/6`'s own default) is the
  budget for the final walk-onto-the-tile step only — a caller whose
  own world is large enough that even the PRE-adjacency march can run
  long (story 916's own larger, multi-vassal worlds) passes a bigger
  figure through `subjugate/6`.
  """
  def capture_city(
        attacker_play_live,
        world,
        user,
        attacker,
        defender_user,
        city,
        max_turns \\ 40
      ) do
    broken_city = grind_city(attacker_play_live, world, attacker, defender_user, city)
    attacker = march_to(attacker_play_live, world, user, attacker, city.tile_id, max_turns)
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

  # Minimum RAW (unrestricted-adjacency, exactly `Visibility.vision_ball/3`'s
  # own BFS) hex-distance `a_freshly_subjugated_vassal_of_a_tyrant/1`
  # marches `my_lord` away from `other_city`'s own tile — see that
  # function's own doc. Wes's own only remaining unit once the war ends
  # is his Lord, standing ON `other_city`'s own tile
  # (`Visibility.vision_radius(:lord) == 3`); a unit adjacent (1 hop) to
  # wherever `my_lord` ends up could be as close as `radius - 1` hops
  # from `other_city` in the worst case, so `radius - 1` must clear `3`
  # — `6` leaves a full hop of headroom over the `5` that bound alone
  # would require.
  @rebellion_lord_exile_radius 6

  # A LAND tile at EXACTLY `radius` raw hex-hops from `from_tile` (per
  # `Fixtures.adjacent_tiles/2`'s own unrestricted mesh adjacency — the
  # SAME graph `Visibility.vision_ball/3` walks, never land-restricted,
  # since a land-restricted search could under-count the real distance a
  # water shortcut gives vision), growing `radius` outward one extra hop
  # at a time (bounded) if the exact-`radius` frontier happens to be all
  # water. `march_to/5`'s own generous default `max_turns` (`40`) absorbs
  # however much longer the REAL, land-only walking route ends up being
  # to actually reach it.
  defp far_land_tile(world, from_tile, radius) do
    Enum.reduce_while(radius..(radius + 15), nil, fn hops, _ ->
      frontier =
        Enum.reduce(1..hops, {[from_tile], MapSet.new([from_tile])}, fn _, {frontier, seen} ->
          next =
            frontier
            |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
            |> Enum.uniq()
            |> Enum.reject(&MapSet.member?(seen, &1))

          {next, MapSet.union(seen, MapSet.new(next))}
        end)
        |> elem(0)

      case Enum.filter(frontier, &(Fixtures.tile_class(world, &1) == :land)) do
        [tile | _] -> {:halt, tile}
        [] -> {:cont, nil}
      end
    end)
  end

  @doc """
  Generalizes `a_freshly_subjugated_vassal/1` into story 919's own
  "holding the FREED cities wins independence" happy path
  (`Criterion7752Spex`/`Criterion7755Spex`): subjugates `context.
  other_user` exactly as that function does, then drives `context.user`
  (the lord) to the MAXIMAL tyrant reading `Rebellion.Resolution.
  tyranny_score/2` can produce — Honor 0 (via the test-only `Fixtures.
  set_player_honor/3`, the same documented, narrow-exception status
  `Fixtures.set_player_gold/3` already has for a figure this codebase
  has no fast real path to) and a 100% tribute rate (via the REAL
  `"set_tribute_rate"` event `GameLive.Play` already ships, story 908 —
  no seam needed, the lord can always raise their own vassal's rate to
  its own real `1.0` ceiling).

  `tyranny_score(0, 1.0) == round((100 - 0) * 0.5 + 1.0 * 100 * 0.5) ==
  100`, which is `>= city_resistance/2`'s own full `0..100` range — so
  `context.other_city` rises to the rebel on ANY seed once independence
  is declared, deterministically, without depending on this scenario's
  own fixture world's own seed happening to produce a low-resistance
  city. The city RISING is still `Rebellion.Resolution` computing that
  for real off these two real, played-to inputs — this given only forces
  the INPUTS (a precondition), never the rise/independence verdict
  itself.

  Also marches `my_lord` off `other_city`'s own tile once captured, all
  the way out to `far_land_tile/3`'s own `@rebellion_lord_exile_radius`
  — for TWO real, independent reasons a caller relying on this given
  needs both of:

    * No leftover defecting garrison. `do_declare_independence/3`'s own
      `rise_cities/5` defects WHICHEVER of the lord's own units is still
      literally standing on a risen city's tile the moment independence
      is declared (criterion 7733's own real, already-shipped behavior).
      Left in place, `a_freshly_subjugated_vassal/1`'s own capturing
      Lord unit would defect to the rebel the instant this city rises —
      correct behavior, but it would (a) silently inflate a caller's own
      before/after unit-roster delta (criterion 7755's own "the
      temporary army disbands" check) with a PERMANENT defector that was
      never part of the temporary army, and (b) far worse, SWAP OWNERSHIP
      of the very unit criterion 7755's own given steps go on to kill via
      a scripted barbarian strike (intended as the FORMER LORD's own
      death, for the heir mechanic) — a defected unit would make that
      kill land on the REBEL's own unit instead, silently breaking "Lord
      Mira's own realm is leaderless" entirely.
    * No stray visible barbarian. Criterion 7755's own given steps spawn
      a throwaway barbarian ADJACENT to `context.my_lord`'s own position
      (required for `Combat.validate_attack/3`'s own adjacency check) to
      deliver that same scripted kill, and never remove it afterward —
      it has no camp/AI (`Fixtures.spawn_barbarian/2`'s own "ownerless,
      no AI" default), so it sits there, alive, for the rest of the
      scenario. Left near `other_city` (my_lord's own old position),
      that barbarian would fall within Wes's own Lord's `vision_radius
      (:lord) == 3` for the ENTIRE rest of the war, and `"game:units"`
      pushes fog-visible enemies alongside a player's own units
      (`Visibility.filter/2`) — silently inflating criterion 7755's own
      post-war unit count with a unit that was never Wes's, was never
      part of the temporary army, and was never meant to be "seen" at
      all. Exiling the lord (and therefore the barbarian, spawned
      adjacent to wherever it ends up) well outside that radius keeps
      the kill real while keeping it invisible to the one player whose
      own roster this given's callers go on to inspect.

  Returns the exact same `context` shape `a_freshly_subjugated_vassal/1`
  does (`:my_lord` — now far off `other_city`'s own tile — `:play_live`,
  `:other_play_live`, `:other_city`, plus whatever `join_and_found_
  rival_city/1` already carries).

  Requires `:a_world`, `:registered_player`, `:second_registered_player`
  already run.
  """
  def a_freshly_subjugated_vassal_of_a_tyrant(context) do
    context = a_freshly_subjugated_vassal(context)

    :ok = Fixtures.set_player_honor(context.world, context.user, 0)

    render_hook(context.play_live, "set_tribute_rate", %{
      "vassal_user_id" => to_string(context.other_user.id),
      "rate" => "100"
    })

    exile_tile =
      far_land_tile(context.world, context.other_city.tile_id, @rebellion_lord_exile_radius)

    my_lord =
      march_to(context.play_live, context.world, context.user, context.my_lord, exile_tile, 80)

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

  `max_turns` (default 40) is the PRE-adjacency march's own budget,
  passed straight through to `capture_city/7`'s own final walk-in
  step too — a caller subjugating several vassals in a row on a LARGE
  world (story 916's own multi-vassal, room-for-five worlds) can land
  arbitrarily far from the lord's own current position each time and
  needs real headroom over the default (QA issue 916-fixture-march:
  `three_vassals_of_one_lord`'s own second and third vassal silently
  never actually became vassals at the default budget — `grind_city/6`
  attacked a target the lord's own unit was never actually adjacent
  to, landing zero damage every round, with no crash to signal it).
  """
  def subjugate(world, lord_conn, lord_user, vassal_conn, vassal_user, max_turns \\ 40) do
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

    # QA issue 916-fixture-adjacency: `adjacent_land_tile/3` picks the
    # FIRST land neighbor with no occupancy check of its own — the
    # vassal's own un-moved Lord unit (their starting pair spawns a
    # Lord alongside the Settler that founds the city, and nothing
    # here ever moves it) can sit RIGHT ON that neighbor, silently
    # walling off the only route in: `march_to/6`'s queued order stalls
    # `:interrupted` one hop short forever, no crash, no timeout ever
    # resolves it. Excluding every tile the vassal's own units
    # currently occupy — not just the lord's own starting tile — picks
    # a neighbor that's actually enterable.
    vassal_unit_tiles = for u <- Fixtures.player_units(world, vassal_user), do: u.tile_id

    target =
      adjacent_land_tile(world, vassal_city.tile_id, [lord_unit.tile_id | vassal_unit_tiles])

    lord_unit = march_to(lord_play_live, world, lord_user, lord_unit, target, max_turns)

    {lord_unit, _broken_city} =
      capture_city(
        lord_play_live,
        world,
        lord_user,
        lord_unit,
        vassal_user,
        vassal_city,
        max_turns
      )

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

    # Story 909/910: this scouting mount is about to be superseded
    # below — closed out first (`go_offline/1`) so it stops holding
    # `Presence.online?/2`'s own registration open. `Presence`'s own
    # `:duplicate` Registry keys mean ANY live connection counts as
    # "online" (multi-tab support, by design) — this function used to
    # leave every earlier remount silently connected forever, which
    # story 901's own alliance specs never noticed (nothing before
    # story 909 ever asked "is this player still connected"), but
    # would permanently strand this pair's own `play_live_a`/
    # `play_live_b` as "online" for story 910's own stewardship specs,
    # no matter how many times a caller's own `go_offline/1` closed the
    # FINAL, returned pair.
    go_offline(play_live_a)

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

    go_offline(play_live_a)
    go_offline(play_live_b)

    {:ok, play_live_a, _html} = live(conn_a, "/play/#{world.id}")
    {:ok, play_live_b, _html} = live(conn_b, "/play/#{world.id}")

    %{play_live_a: play_live_a, play_live_b: play_live_b}
  end

  @doc """
  Story 912's own locked gold formula (`BrokenOaths.Cities.Yields.
  base_gold/1`/`tile_gold/1`), recomputed here from sanctioned reads
  only (`Fixtures.player_cities/2`/`Fixtures.tile_terrain/2`) — never a
  direct call into `BrokenOaths.Cities.Yields` itself, which the spex
  Boundary forbids (`BrokenOathsSpex.Fixtures` is the only module
  allowed to dep on `BrokenOaths`). `1 + floor(size/2)` per city, plus
  1 more per currently WORKED Coast tile, summed across every city
  `user` owns in `world`.

  Story 908/909's own tribute/bank criteria used to hand-set an
  arbitrary per-turn income (`Fixtures.set_player_gold_income/3`)
  before story 912 shipped a real per-turn city gold income mechanic —
  now that `WorldServer`'s `apply_tribute/1`/`apply_bank/1` compute the
  REAL figure every boundary, `Fixtures.set_player_gold_income/3` no
  longer feeds either phase at all (see both modules' own moduledocs).
  This is the reconciled specs' own sanctioned way to compute what
  tribute/bank SHOULD move without re-deriving the formula from raw
  game internals or hardcoding a magic number that would drift the
  moment a city grows, a worked tile changes, or marching/siege turns
  vary between runs.
  """
  def real_gold_income(world, user) do
    for city <- Fixtures.player_cities(world, user) do
      coast_tiles =
        Enum.count(city.worked_tiles, &(Fixtures.tile_terrain(world, &1).base == :coast))

      1 + div(city.size, 2) + coast_tiles
    end
    |> Enum.sum()
  end

  @doc """
  Advances real turn boundaries, bounded at `max_turns`, until
  `city_id` (owned by `user` in `world`) reaches `target_size` — the
  same halt-on-condition loop already inlined in several growth specs
  (`criterion_7475`/`criterion_7625`/`criterion_7646`), extracted here
  so story 912's own reconciled tribute/bank specs can grow a captured
  vassal's city to a MEANINGFUL, non-trivial gold income (a freshly
  founded size-1 city earns only the 1-gold base — see
  `BrokenOathsSpex.Story912CityGoldIncome.Criterion7714Spex`) without
  depending on however many turns a march/siege happened to burn.
  Growth (and food accrual) proceeds every real boundary regardless of
  the OWNER's online/offline status, so this works identically whether
  called before or after `go_offline/1`. A no-op once `target_size` is
  already met.
  """
  def grow_city_to(world, user, city_id, target_size, max_turns \\ 250) do
    Enum.reduce_while(1..max_turns, :ok, fn _, :ok ->
      [city] = for c <- Fixtures.player_cities(world, user), c.id == city_id, do: c

      if city.size >= target_size do
        {:halt, :ok}
      else
        Fixtures.advance_turn(world)
        {:cont, :ok}
      end
    end)
  end

  # -------------------------------------------------------------------
  # Rebellion batch helpers (story 915 and friends): a lord who already
  # holds one vassal occupying MULTIPLE cities, and a way to depress
  # that same lord's world-visible Honor via a REAL, already-shipped
  # dishonorable act (story 906's garrison-execution choice) against a
  # THROWAWAY third party — see each calling criterion's own moduledoc
  # for why these are kept generic here rather than duplicated inline a
  # third time.
  # -------------------------------------------------------------------

  @doc """
  Generalizes `a_freshly_subjugated_vassal/1` to TWO cities — the
  tractable substitute story 915's own multi-city rebellion criteria
  (7732/7734/7736) use in place of the gherkin's own illustrative "5
  occupied cities": a real settler-founded second city costs dozens of
  real turn boundaries by itself (growth to size 2, settler production,
  a multi-ring march to a legal founding spot — see
  `BrokenOathsSpex.Story907.Criterion7667Spex`'s own inline version of
  this exact setup), so 5 real cities would be disproportionate setup
  cost for what these criteria are actually about (the per-city
  rise/stay formula and its downstream UI, not "found N cities"). TWO
  is the minimum that still lets a scenario distinguish "some cities
  rise, some stay loyal" from "the whole relationship flips as one
  unit" — see each calling criterion's own moduledoc for how it reads
  the actual split rather than assuming one.

  Both captured cities are left WITHOUT any of the lord's own units
  still standing on them afterward (the final step below marches the
  lord's own Lord unit off the last-captured city, back toward a
  neutral tile) — story 915's own temporary-rebellion-army criteria
  (7734) need to count NEWLY SPAWNED units on the rebel's own side
  without a leftover defecting garrison confounding that count. A
  criterion that specifically needs a lord's unit LEFT stationed on an
  occupied city as a garrison (7733) does not use this helper — see its
  own moduledoc.

  Returns context extended with `:my_lord`, `:other_city` (the FIRST
  city founded — captured LAST, since it's the rival's own last free
  city, so this is the capture that fires vassalization), `:second_city`
  (founded second, captured FIRST while the rival still had a free city
  elsewhere, so this capture alone does NOT trigger vassalization —
  mirrors `criterion_7667`'s own "occupying a non-last city leaves the
  owner free" fact).

  Requires `:a_world`, `:registered_player`, `:second_registered_player`
  already run.
  """
  def a_freshly_subjugated_vassal_with_two_cities(context) do
    context = join_and_found_rival_city(context)
    :ok = clear_all_camps(context.world)

    first_city = context.other_city

    grow_city_to(context.world, context.other_user, first_city.id, 2)

    render_hook(context.other_play_live, "queue_production", %{
      "city_id" => to_string(first_city.id),
      "item" => "settler"
    })

    for _ <- 1..20, do: Fixtures.advance_turn(context.world)

    [new_settler] =
      for u <- Fixtures.player_units(context.world, context.other_user),
          u.type == :settler,
          do: u

    land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

    ring4 =
      Enum.reduce(1..4, {[first_city.tile_id], MapSet.new([first_city.tile_id])}, fn _,
                                                                                     {frontier,
                                                                                      seen} ->
        next =
          frontier
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))
          |> Enum.filter(land?)

        {next, MapSet.union(seen, MapSet.new(next))}
      end)
      |> elem(0)

    [second_target | _] = ring4

    settler =
      march_to(
        context.other_play_live,
        context.world,
        context.other_user,
        new_settler,
        second_target
      )

    render_hook(context.other_play_live, "found_city", %{"unit_id" => to_string(settler.id)})

    [second_city] =
      for c <- Fixtures.player_cities(context.world, context.other_user),
          c.id != first_city.id,
          do: c

    [my_lord] =
      for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

    # Capture the SECOND city first — the rival still has a free city
    # (`first_city`), so this does not trigger vassalization yet
    # (`criterion_7667`'s own guarantee).
    target2 = adjacent_land_tile(context.world, second_city.tile_id, [my_lord.tile_id])
    my_lord = march_to(context.play_live, context.world, context.user, my_lord, target2)

    {my_lord, _} =
      capture_city(
        context.play_live,
        context.world,
        context.user,
        my_lord,
        context.other_user,
        second_city
      )

    # Capture the FIRST city last — the rival's own last free city, so
    # THIS capture fires vassalization.
    target1 = adjacent_land_tile(context.world, first_city.tile_id, [my_lord.tile_id])
    my_lord = march_to(context.play_live, context.world, context.user, my_lord, target1)

    {my_lord, _} =
      capture_city(
        context.play_live,
        context.world,
        context.user,
        my_lord,
        context.other_user,
        first_city
      )

    # Leave neither captured city garrisoned by the lord's own Lord
    # unit — march it off to a neutral spot so a later "count the
    # rebel's own newly spawned units" check isn't confounded by a
    # defecting garrison (see this function's own doc).
    neutral = adjacent_land_tile(context.world, first_city.tile_id, [second_city.tile_id])
    my_lord = march_to(context.play_live, context.world, context.user, my_lord, neutral)

    context
    |> Map.put(:my_lord, my_lord)
    |> Map.put(:other_city, first_city)
    |> Map.put(:second_city, second_city)
  end

  @doc """
  Depresses `context.user`'s (the lord's) global Honor via a REAL,
  already-shipped dishonorable act: executing a captured garrison
  "costs Honor" (`.code_my_spec/knowledge/feudal_vassalage_design.md`,
  "Round-4 final foundation mechanics"), already wired end-to-end since
  story 906 (`BrokenOaths.Combat.Siege.apply_execute_honor_penalty/1`,
  the real `"resolve_garrison_fate"` event — see
  `BrokenOathsSpex.Story906.Criterion7662Spex`). Honor is described as
  the lord's own WORLD-VISIBLE reputation
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Rebellion
  batch"), not a per-relationship figure, so this depresses it against
  a THROWAWAY third victim (`context.third_user`, never `context.
  other_user` — the vassal a calling story 915 criterion's own scenario
  is actually about) — the same lord-global reputation story 915's own
  rise/stay-loyal formula is meant to read, established without
  entangling a garrisoned-siege setup with whatever OTHER city/vassal
  the calling scenario's own `given_` builds separately.

  Leaves `context.user`'s own Lord unit standing on the throwaway
  victim's city tile once done — callers whose own scenario needs that
  unit back at a DIFFERENT tile (e.g. still garrisoning the actual
  vassal under test) march it there as an explicit follow-up step; this
  helper does not know or care where it's needed next.

  Requires `context.world`, `context.user`/`context.conn`/`context.
  play_live` (already joined and mounted — e.g. by a prior
  `a_freshly_subjugated_vassal/1` or `a_freshly_subjugated_vassal_
  with_two_cities/1` call), and `context.third_user`/`context.
  third_conn` — run `:a_world`, `:registered_player`, and
  `:third_registered_player` first.
  """
  def lord_executes_a_throwaway_garrison(context) do
    {:ok, third_join_live, _html} = live(context.third_conn, "/play")

    third_join_live
    |> element("[data-test='join-world-#{context.world.id}']")
    |> render_click()

    {:ok, third_play_live, _html} = live(context.third_conn, "/play/#{context.world.id}")

    [third_settler | _] =
      for u <- Fixtures.player_units(context.world, context.third_user),
          u.type == :settler,
          do: u

    render_hook(third_play_live, "found_city", %{"unit_id" => to_string(third_settler.id)})
    [third_city] = Fixtures.player_cities(context.world, context.third_user)

    :ok = clear_all_camps(context.world)

    [my_lord] =
      for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

    target = adjacent_land_tile(context.world, third_city.tile_id, [my_lord.tile_id])
    my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

    grind_city(context.play_live, context.world, my_lord, context.third_user, third_city)

    render_hook(third_play_live, "queue_production", %{
      "city_id" => to_string(third_city.id),
      "item" => "warrior"
    })

    for _ <- 1..12, do: Fixtures.advance_turn(context.world)

    [garrison] =
      for u <- Fixtures.player_units(context.world, context.third_user),
          u.type == :warrior,
          do: u

    _garrison =
      if garrison.tile_id == third_city.tile_id do
        garrison
      else
        march_to(third_play_live, context.world, context.third_user, garrison, third_city.tile_id)
      end

    _ =
      march_to(context.play_live, context.world, context.user, my_lord, third_city.tile_id)

    render_hook(context.play_live, "resolve_garrison_fate", %{
      "city_id" => to_string(third_city.id),
      "choice" => "execute"
    })

    context
  end

  # -------------------------------------------------------------------
  # Story 916 (Coordinated Rebellion — Pact of Broken Oaths) helpers.
  # See `BrokenOathsSpex.Story916.Criterion7737Spex`'s own moduledoc for
  # the full assumed `RebellionPact` surface contract these two givens
  # (and every story 916 spec) drive.
  # -------------------------------------------------------------------

  @doc false
  # Three fellow vassals of the SAME lord (`context.user`) — story
  # 916's own "Wes, Ada, and Bo are all vassals of Lord Mira"
  # precondition, needed by every criterion in that story (five
  # separate spec files), crossing this module's own "only after a
  # third duplicate" shared-given threshold (`shared_givens.md`).
  # Captures each vassal one after another via `subjugate/5` — exactly
  # the "multi-vassal-under-one-lord" general form that function's own
  # doc names as the seam for "story 910's own 'fellow vassal'
  # criteria" and, now, story 916's own conspiracy roster — taking
  # each one offline right after capture (`go_offline/1`) the same way
  # `BrokenOathsSpex.Story908.Criterion7679Spex`'s own three-vassal
  # loop does: an idle, disconnected `GameLive.Play` mount left open
  # per vassal would otherwise stay registered forever against this
  # scenario's later turn boundaries for no reason story 916 cares
  # about.
  #
  # Requires `context.world` (sized for FOUR players — one lord, three
  # vassals) and `context.user`/`context.conn` (the lord) from a prior
  # `:a_world`-shaped given + `:registered_player`. Produces
  # `context.pact_vassals`, a 3-element list of `%{user:, conn:}` in
  # Wes/Ada/Bo order (list order IS the story's own naming order —
  # every calling spec destructures `[wes, ada, bo] = context.
  # pact_vassals`) — deliberately bare, no live `play_live` handle
  # carried forward: every story 916 spec re-mounts each vassal's own
  # `GameLive.Play` fresh at the point it actually needs to drive or
  # observe something, the same "mount fresh, don't trust a stale
  # handle" discipline `BrokenOathsSpex.Story913.Criterion7720Spex`'s
  # own `when_` step already uses.
  #
  # Passes a generous `250`-turn march budget through `subjugate/6`
  # (default `40`, tuned for `world_fixture/1`'s own small default
  # 642-tile globe) — story 916's own worlds are deliberately LARGER
  # ("room for four/five players", frequency 10-12), so a fresh
  # vassal's own claimed region can land far enough from the lord's
  # own CURRENT position (already displaced by the prior vassal's own
  # capture march) that the default budget silently never gets the
  # lord adjacent at all: `grind_city/6` still "succeeds" (no crash,
  # `attempt_event`-shaped `"attack"` calls just never land — see
  # `Game.attack_city/4`'s own `:not_adjacent` refusal) while doing
  # zero damage every round, so the SECOND and THIRD vassal in the
  # loop never actually became vassals under the old default — this
  # was a bug in this given's own fixture, not in any spec's `then_`.
  register_given :three_vassals_of_one_lord, context do
    vassals =
      for _ <- 1..3 do
        vassal_user = Fixtures.user_fixture()

        vassal_conn =
          Phoenix.ConnTest.build_conn()
          |> BrokenOathsTest.ConnCase.log_in_user(vassal_user)

        %{vassal_play_live: vassal_play_live} =
          subjugate(context.world, context.conn, context.user, vassal_conn, vassal_user, 250)

        go_offline(vassal_play_live)

        %{user: vassal_user, conn: vassal_conn}
      end

    {:ok, Map.put(context, :pact_vassals, vassals)}
  end

  @doc false
  # Wes (the first of `context.pact_vassals`) opens a Pact of Broken
  # Oaths naming strike turn 50 and invites Ada and Bo (the other two)
  # into it — the exact precondition four of story 916's five own
  # criteria need as SETUP rather than as their own subject under test
  # (only `Criterion7737Spex` drives this action itself as its own
  # `when_`, so that file intentionally does NOT use this given).
  # Driven via `attempt_event/3` against the INVENTED `"open_pact_chat"`
  # hook — see `Criterion7737Spex`'s own moduledoc for the full assumed
  # event/param/selector contract.
  #
  # Requires `context.world` and `context.pact_vassals` — run
  # `:three_vassals_of_one_lord` first. Produces `context.wes`/
  # `context.ada`/`context.bo`, the same three `%{user:, conn:}` maps
  # `context.pact_vassals` already carries, just destructured under
  # their own story names for every downstream step's convenience.
  register_given :wes_opened_pact_inviting_ada_and_bo, context do
    [wes, ada, bo] = context.pact_vassals

    {:ok, wes_live, _html} = live(wes.conn, "/play/#{context.world.id}")

    attempt_event(wes_live, "open_pact_chat", %{
      "strike_turn" => "50",
      "invitee_user_ids" => [to_string(ada.user.id), to_string(bo.user.id)]
    })

    {:ok, context |> Map.put(:wes, wes) |> Map.put(:ada, ada) |> Map.put(:bo, bo)}
  end
end
