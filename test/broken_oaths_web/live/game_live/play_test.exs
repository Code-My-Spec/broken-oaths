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
  # `BrokenOaths.Simulation.WorldServer` GenServer, a process outside this
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
  # Owner rings + click-to-inspect — telling one player's units apart
  # from another's, and reading a unit's stats on click.
  # -------------------------------------------------------------------

  describe "unit owner identity + inspect" do
    test "the units payload carries an owner identity that differs between two players", %{
      conn: conn,
      world: world,
      user: user
    } do
      other_user = BrokenOathsSpex.Fixtures.user_fixture()

      other_conn =
        Phoenix.ConnTest.build_conn() |> BrokenOathsTest.ConnCase.log_in_user(other_user)

      {:ok, _play_live, _html} = join_and_mount(conn, world)

      {:ok, other_join_live, _html} = live(other_conn, ~p"/play")
      other_join_live |> element("[data-test='join-world-#{world.id}']") |> render_click()
      {:ok, _other_play_live, _html} = live(other_conn, ~p"/play/#{world.id}")

      {:ok, player_a} = Game.join_world(world, user)
      {:ok, player_b} = Game.join_world(world, other_user)
      assert player_a.id != player_b.id

      units_a = Game.units_visible_to(world, user)
      units_b = Game.units_visible_to(world, other_user)

      # Each player's OWN units carry `own: true` and that player's own
      # `player_id` — the board hook draws its owner ring off exactly
      # these, so two different players never render the same color.
      assert units_a != []
      assert Enum.all?(units_a, &(&1.own and &1.player_id == player_a.id))

      assert units_b != []
      assert Enum.all?(units_b, &(&1.own and &1.player_id == player_b.id))
    end

    test "clicking a unit surfaces its inspect readout and keeps it selected for orders", %{
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

      # The inspect readout: type, owner, HP, and movement all show.
      html = render(play_live)
      assert html =~ ~s(data-test="unit-panel")
      assert html =~ ~s(data-test="unit-type")
      assert html =~ ~s(data-test="unit-owner")
      assert html =~ "You"
      assert html =~ ~s(data-test="unit-hp")
      assert html =~ ~s(data-test="unit-movement")

      # Inspect must not break move orders — the selection is still live,
      # so the board can right-click a destination for this same unit.
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

  # -------------------------------------------------------------------
  # Playtest issue 6 — "task complete" toasts: research finishing and a
  # city finishing production both toast the OWNING player the instant
  # they land, reusing the existing "game:alert" push convention.
  # -------------------------------------------------------------------

  describe "task/completion notifications (playtest issue 6)" do
    test "a completed (non-Bronze-Working) tech toasts \"Researched <Tech>.\"", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      found_first_city(play_live, world, user)

      render_hook(play_live, "toggle_tech_panel", %{})
      render_hook(play_live, "select_research", %{"tech" => "pottery"})

      # A lone size-1 city earns 2 science/turn (`Research.
      # science_per_turn/1`); Pottery costs 80 (QA issue d95ea179
      # rebalance) — ceil(80/2) == 40. 45 is a safe overshoot.
      Enum.reduce_while(1..45, :ok, fn _, :ok ->
        if :pottery in Game.player_research(world, user).completed_techs do
          {:halt, :ok}
        else
          Game.advance_turn(world)
          {:cont, :ok}
        end
      end)

      assert :pottery in Game.player_research(world, user).completed_techs
      assert_push_event(play_live, "game:alert", %{message: "Researched Pottery."}, 500)
    end

    test "a finished production item toasts \"Built <thing> in <City>.\"", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      {city, _camps} = found_first_city(play_live, world, user)

      render_hook(play_live, "queue_production", %{
        "city_id" => to_string(city.id),
        "item" => "warrior"
      })

      # The flat production base is 5/turn (`Production.flat_base/0`) —
      # a Warrior costs 40, so ceil(40/5) == 8 turns even with zero
      # worked-tile production on top. 12 is a safe overshoot.
      Enum.reduce_while(1..12, :ok, fn _, :ok ->
        if Enum.any?(Game.player_units(world, user), &(&1.type == :warrior)) do
          {:halt, :ok}
        else
          Game.advance_turn(world)
          {:cont, :ok}
        end
      end)

      assert Enum.any?(Game.player_units(world, user), &(&1.type == :warrior))
      expected = "Built Warrior in #{city.name}."
      assert_push_event(play_live, "game:alert", %{message: ^expected}, 500)
    end
  end

  # -------------------------------------------------------------------
  # Playtest issue 4 — clicking a Known Players row centers the globe on
  # that player's nearest tile the viewer can currently see.
  # -------------------------------------------------------------------

  describe "center on player (playtest issue 4)" do
    test "pushes globe3d:center at the target's own visible tile", %{
      conn: conn,
      world: world,
      user: user
    } do
      other_user = BrokenOathsSpex.Fixtures.user_fixture()

      other_conn =
        Phoenix.ConnTest.build_conn() |> BrokenOathsTest.ConnCase.log_in_user(other_user)

      {:ok, play_live, _html} = join_and_mount(conn, world)

      {:ok, other_join_live, _html} = live(other_conn, ~p"/play")
      other_join_live |> element("[data-test='join-world-#{world.id}']") |> render_click()
      {:ok, _other_play_live, _html} = live(other_conn, ~p"/play/#{world.id}")

      [my_lord] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      [other_lord] = for u <- Game.player_units(world, other_user), u.type == :lord, do: u

      occupied =
        for u <- Game.player_units(world, user) ++ Game.player_units(world, other_user),
            do: u.tile_id

      [target | _] =
        world
        |> Regions.adjacent_tiles(my_lord.tile_id)
        |> Enum.filter(&(Regions.tile_class(world, &1) == :land))
        |> Enum.reject(&(&1 in occupied))

      :ok = BrokenOathsSpex.Fixtures.relocate_unit(world, other_lord.id, target)
      # A turn boundary both runs first-contact detection (so the row
      # actually exists — a stranger is never clickable before
      # discovery) and refreshes explored/visible sets.
      Game.advance_turn(world)

      assert has_element?(play_live, "[data-test='known-player-#{other_user.id}']")

      render_hook(play_live, "center_on_player", %{"user_id" => to_string(other_user.id)})

      mesh = BrokenOaths.Worlds.Globe.get(world.frequency)

      {expected_yaw, expected_pitch} =
        BrokenOathsWeb.GameLive.PlayView.camera_on([%{tile_id: target}], mesh)

      assert_push_event(play_live, "globe3d:center", %{yaw: ^expected_yaw, pitch: ^expected_pitch})
    end

    test "a click on a known player currently out of sight is a quiet no-op", %{
      conn: conn,
      world: world,
      user: user
    } do
      other_user = BrokenOathsSpex.Fixtures.user_fixture()

      other_conn =
        Phoenix.ConnTest.build_conn() |> BrokenOathsTest.ConnCase.log_in_user(other_user)

      {:ok, play_live, _html} = join_and_mount(conn, world)

      {:ok, other_join_live, _html} = live(other_conn, ~p"/play")
      other_join_live |> element("[data-test='join-world-#{world.id}']") |> render_click()
      {:ok, _other_play_live, _html} = live(other_conn, ~p"/play/#{world.id}")

      [my_lord] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      [other_lord] = for u <- Game.player_units(world, other_user), u.type == :lord, do: u

      occupied =
        for u <- Game.player_units(world, user) ++ Game.player_units(world, other_user),
            do: u.tile_id

      [target | _] =
        world
        |> Regions.adjacent_tiles(my_lord.tile_id)
        |> Enum.filter(&(Regions.tile_class(world, &1) == :land))
        |> Enum.reject(&(&1 in occupied))

      :ok = BrokenOathsSpex.Fixtures.relocate_unit(world, other_lord.id, target)
      Game.advance_turn(world)
      assert has_element?(play_live, "[data-test='known-player-#{other_user.id}']")

      # Move them back out of sight (still known — discovery is
      # permanent, story 899) and advance again so the fog updates.
      # `my_lord`'s own vision radius is 3 (`Visibility.vision_radius/1`)
      # — pick a tile entirely outside that ball, not merely non-adjacent.
      my_ball = BrokenOaths.Vision.Visibility.visible_tiles(world, [my_lord])

      far_tile =
        Enum.find(
          0..(BrokenOaths.Worlds.Globe.tile_count(world.frequency) - 1),
          &(&1 not in my_ball)
        )

      :ok = BrokenOathsSpex.Fixtures.relocate_unit(world, other_lord.id, far_tile)
      Game.advance_turn(world)

      render_hook(play_live, "center_on_player", %{"user_id" => to_string(other_user.id)})
      refute_push_event(play_live, "globe3d:center", %{})
    end
  end
end
