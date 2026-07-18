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
end
