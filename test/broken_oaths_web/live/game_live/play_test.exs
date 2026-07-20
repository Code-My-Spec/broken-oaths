defmodule BrokenOathsWeb.GameLive.PlayTest do
  @moduledoc """
  v0.2.1 playtest UI/UX fixes (QA issues e51a31be, 748348fe,
  759d02c8/0b8a75e4, 937ea82b) — regular ConnCase LiveView tests, not
  spex/BDD. These assert the server-side/DOM-level behavior each fix
  produces: selection state, the pushed client events, and panel
  markup. Visual confirmation of the actual canvas rendering (borders,
  highlights, close-button placement) is a separate browser QA pass.
  """

  # `async: false` — mounting `GameLive.Play` spawns a real
  # `BrokenOaths.Game.WorldServer` GenServer, a process outside this
  # test's own sandbox ownership; the DB sandbox only auto-allows
  # other processes when it's running in SHARED mode (`async: false`
  # here — see `BrokenOathsTest.DataCase.setup_sandbox/1`'s own
  # `shared: not tags[:async]`), the same non-async status every
  # `BrokenOathsSpex.Case`-based spec that mounts `Play` already has.
  use BrokenOathsTest.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BrokenOaths.WorldsFixtures

  alias BrokenOaths.Game
  alias BrokenOaths.Combat.Camp
  alias BrokenOaths.Worlds.Regions

  setup :register_and_log_in_user

  setup do
    {:ok, world: world_fixture(%{seed: 424_242})}
  end

  defp join_and_mount(conn, world) do
    {:ok, join_live, _html} = live(conn, ~p"/play")

    join_live
    |> element("[data-test='join-world-#{world.id}']")
    |> render_click()

    live(conn, ~p"/play/#{world.id}")
  end

  defp found_first_city(play_live, world, user) do
    [settler | _] = for u <- Game.player_units(world, user), u.type == :settler, do: u
    render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
    # "game:camps" pushes unconditionally the first time a (non-empty)
    # camp set exists (story 892 seeds wilderness camps on first
    # founding) — waiting on it guarantees the SAME refresh_board/1
    # call has already landed `cities` in this view's own assigns
    # before the next render_hook/3 reads them.
    assert_push_event(play_live, "game:camps", %{camps: camps}, 500)
    [city] = Game.player_cities(world, user)
    {city, camps}
  end

  # -------------------------------------------------------------------
  # Issue e51a31be — the detail pane is dismissible, content-sized, and
  # doesn't cover the rest of the UI
  # -------------------------------------------------------------------

  describe "the detail pane's close control (QA issue e51a31be)" do
    test "closing the tile panel clears the selection", %{conn: conn, world: world, user: user} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      render_hook(play_live, "select_tile", %{"tile_id" => lord.tile_id})

      html = render(play_live)
      assert html =~ ~s(data-test="detail-pane")
      assert html =~ ~s(data-test="tile-panel")

      html =
        play_live
        |> element("[data-test='close-tile-panel']")
        |> render_click()

      refute html =~ ~s(data-test="detail-pane")
      refute html =~ ~s(data-test="tile-panel")
    end

    test "closing the unit panel clears the selection", %{conn: conn, world: world, user: user} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      render_hook(play_live, "select_unit", %{"unit_id" => lord.id})

      html = render(play_live)
      assert html =~ ~s(data-test="unit-panel")

      html =
        play_live
        |> element("[data-test='close-unit-panel']")
        |> render_click()

      refute html =~ ~s(data-test="detail-pane")
      refute html =~ ~s(data-test="unit-panel")
    end

    test "closing the city panel clears the selection", %{conn: conn, world: world, user: user} do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      {city, _camps} = found_first_city(play_live, world, user)

      render_hook(play_live, "select_city", %{"city_id" => city.id})
      html = render(play_live)
      assert html =~ ~s(data-test="city-panel")

      html =
        play_live
        |> element("[data-test='close-city-panel']")
        |> render_click()

      refute html =~ ~s(data-test="detail-pane")
      refute html =~ ~s(data-test="city-panel")
    end

    test "the generic clear_selection event resets every selection assign", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      render_hook(play_live, "select_unit", %{"unit_id" => lord.id})
      assert render(play_live) =~ ~s(data-test="unit-panel")

      render_hook(play_live, "clear_selection", %{})
      html = render(play_live)
      refute html =~ ~s(data-test="detail-pane")
      refute html =~ ~s(data-test="unit-panel")
    end
  end

  # -------------------------------------------------------------------
  # Issue 748348fe — a barbarian camp is selectable and shows its HP
  # -------------------------------------------------------------------

  describe "selecting a barbarian camp (QA issue 748348fe)" do
    test "surfaces the camp's own HP in the detail pane", %{conn: conn, world: world, user: user} do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      {_city, camps} = found_first_city(play_live, world, user)

      [camp | _] = camps

      html = render_hook(play_live, "select_camp", %{"camp_id" => camp.id})

      assert html =~ ~s(data-test="camp-panel")
      assert html =~ "Barbarian Camp"
      assert html =~ ~s(data-test="camp-hp")
      assert html =~ "#{camp.hp}/#{Camp.max_hp()}"
    end

    test "the camp's HP drops after an attack, watched live", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      {city, camps} = found_first_city(play_live, world, user)

      [camp | _] = camps

      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u

      land? = fn t -> Regions.tile_class(world, t) == :land end

      [target | _] =
        world
        |> Regions.adjacent_tiles(camp.tile_id)
        |> Enum.filter(land?)
        |> Enum.reject(&(&1 in [city.tile_id, lord.tile_id]))

      :ok = Game.relocate_unit_for_test(world, lord.id, target)

      render_hook(play_live, "select_camp", %{"camp_id" => camp.id})
      assert render(play_live) =~ "#{camp.hp}/#{Camp.max_hp()}"

      render_hook(play_live, "attack", %{
        "unit_id" => to_string(lord.id),
        "target_camp_id" => to_string(camp.id)
      })

      assert_push_event(play_live, "game:combat", %{damage_dealt: dealt, damage_taken: 0}, 500)
      assert dealt > 0

      assert_push_event(play_live, "game:camps", %{camps: refreshed_camps}, 500)
      refreshed_camp = Enum.find(refreshed_camps, &(&1.id == camp.id))
      assert refreshed_camp.hp < camp.hp

      html = render(play_live)
      assert html =~ "#{refreshed_camp.hp}/#{Camp.max_hp()}"
    end
  end

  # -------------------------------------------------------------------
  # Issues 759d02c8/0b8a75e4 — city borders/worked tiles pushed for the
  # board renderer, so a panel's raw tile ids correspond to something
  # visible on the board
  # -------------------------------------------------------------------

  describe "selecting a city pushes its territory/worked tiles (QA issues 759d02c8, 0b8a75e4)" do
    test "the payload includes the city's own territory and worked (+ center) tiles", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      {city, _camps} = found_first_city(play_live, world, user)

      render_hook(play_live, "select_city", %{"city_id" => city.id})

      assert_push_event(
        play_live,
        "game:city_selection",
        %{territory: territory, worked_tiles: worked_tiles},
        500
      )

      # Founding territory is the tile plus its six neighbors
      # (Production.founding_territory/2) — at least 7 tiles.
      assert length(territory) >= 7
      assert city.tile_id in territory
      assert city.tile_id in worked_tiles
    end

    test "clearing the selection pushes an empty payload", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      {city, _camps} = found_first_city(play_live, world, user)

      render_hook(play_live, "select_city", %{"city_id" => city.id})
      assert_push_event(play_live, "game:city_selection", %{territory: [_ | _]}, 500)

      render_hook(play_live, "clear_selection", %{})

      assert_push_event(
        play_live,
        "game:city_selection",
        %{territory: [], worked_tiles: []},
        500
      )
    end
  end

  # -------------------------------------------------------------------
  # Issue d403faa6 — clicking a stacked tile (a non-combat unit plus a
  # combat escort, both this player's own — the v0.2.1 field-stacking
  # fix) cycles through its units instead of always resolving to the
  # same one
  # -------------------------------------------------------------------

  describe "cycling through a stacked tile's own units (QA issue d403faa6)" do
    test "first click selects unit A, second selects unit B, third wraps back to A", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      # `spawn_unit_for_test/4` takes the `Players.Player` id, not the
      # `Accounts.User` one — `join_world/2` is idempotent (`do_join/2`
      # just hands back the already-joined row), so this re-fetches it
      # rather than threading a fresh assign through `join_and_mount/2`.
      {:ok, player} = Game.join_world(world, user)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, lord.tile_id)

      [unit_a_id, unit_b_id] = Enum.sort([lord.id, worker.id])

      select_on_tile = fn ->
        render_hook(play_live, "select_unit", %{
          "unit_id" => to_string(lord.id),
          "tile_id" => to_string(lord.tile_id)
        })
      end

      select_on_tile.()
      assert_push_event(play_live, "game:selected", %{unit_id: ^unit_a_id})

      select_on_tile.()
      assert_push_event(play_live, "game:selected", %{unit_id: ^unit_b_id})

      select_on_tile.()
      assert_push_event(play_live, "game:selected", %{unit_id: ^unit_a_id})
    end

    test "a single-unit tile keeps selecting that same unit on repeat clicks", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      lord_id = lord.id

      render_hook(play_live, "select_unit", %{
        "unit_id" => to_string(lord.id),
        "tile_id" => to_string(lord.tile_id)
      })

      assert_push_event(play_live, "game:selected", %{unit_id: ^lord_id})

      render_hook(play_live, "select_unit", %{
        "unit_id" => to_string(lord.id),
        "tile_id" => to_string(lord.tile_id)
      })

      assert_push_event(play_live, "game:selected", %{unit_id: ^lord_id})
    end
  end

  # -------------------------------------------------------------------
  # Issue 937ea82b — a first-pass in-game Help panel
  # -------------------------------------------------------------------

  describe "the Help panel (QA issue 937ea82b)" do
    test "opens from the always-reachable Help button and renders known sections", %{
      conn: conn,
      world: world
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      html = render(play_live)
      assert html =~ ~s(data-test="help-button")
      refute html =~ ~s(data-test="help-modal")

      html =
        play_live
        |> element("[data-test='help-button']")
        |> render_click()

      assert html =~ ~s(data-test="help-modal")
      assert html =~ ~s(data-test="help-section-healing")
      assert html =~ "15 HP"
      assert html =~ ~s(data-test="help-section-barbarians")
      assert html =~ ~s(data-test="help-section-combat")
      assert html =~ ~s(data-test="help-section-tech")
      assert html =~ "Bronze Working"
    end

    test "closes via its own close control", %{conn: conn, world: world} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      play_live |> element("[data-test='help-button']") |> render_click()
      assert render(play_live) =~ ~s(data-test="help-modal")

      html =
        play_live
        |> element("[data-test='close-help']")
        |> render_click()

      refute html =~ ~s(data-test="help-modal")
    end
  end
end
