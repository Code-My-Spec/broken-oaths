defmodule BrokenOathsWeb.GameLive.StewardUiTest do
  @moduledoc """
  QA issue bd93cc0a — real, click-through UI coverage for production
  stewardship (criterion 7690) and emergency defense (criteria 7692/
  7693), story 910. Until now `"steward_queue_production"`/
  `"steward_defend"` were only reachable via `attempt_event/3` in the
  spex suite (`BrokenOathsSpex.Story910.Criterion7690Spex`/
  `Criterion7693Spex`) — no rendered button/form existed for either on
  `GameLive.Play`'s own `vassal_row` or `GameLive.AlliancePanel`'s own
  `alliance_row`. These tests drive the real DOM affordances added to
  both.

  Every check against a LiveView's OWN rendered state re-mounts a
  fresh connection right before reading it (`live/2`, not a stale
  handle) — a fresh mount's own `mount/3` re-pulls `:vassals`
  (`Game.vassals/2`) before it ever replies, so its FIRST render
  reflects the target's current online/under-attack status. Reading
  straight off `BrokenOaths.Game` (raw backend state) is preferred
  wherever it's just as good a signal, the same posture
  `BrokenOathsWeb.GameLive.FeudalCaptureUITest` already establishes.
  """

  # async: false — mounts several real `GameLive.Play` LiveViews
  # sharing one `WorldServer`, same status `FeudalCaptureUITest`/
  # `FeudalFlagTest` already carry.
  use BrokenOathsTest.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BrokenOathsSpex.SharedGivens

  alias BrokenOaths.Game
  alias BrokenOaths.UsersFixtures
  alias BrokenOathsSpex.Fixtures

  setup :register_and_log_in_user

  setup %{conn: conn} do
    other_user = UsersFixtures.user_fixture()
    other_conn = log_in_user(build_conn(), other_user)

    original = Application.get_env(:broken_oaths, :feudal_enabled)
    Application.put_env(:broken_oaths, :feudal_enabled, true)
    on_exit(fn -> Application.put_env(:broken_oaths, :feudal_enabled, original) end)

    {:ok,
     conn: conn,
     world: Fixtures.world_fixture(%{seed: 424_242}),
     other_user: other_user,
     other_conn: other_conn}
  end

  defp found_city(play_live, world, user) do
    [settler | _] = for u <- Game.player_units(world, user), u.type == :settler, do: u
    render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
    [city] = Game.player_cities(world, user)
    city
  end

  describe "production stewardship — vassals panel (QA issue bd93cc0a)" do
    test "a lord steward sets an offline vassal's production from the constructive whitelist, never offering a locked item",
         %{conn: conn, user: lord, other_conn: vassal_conn, other_user: vassal, world: world} do
      %{vassal_play_live: vassal_play_live, vassal_city: vassal_city} =
        subjugate(world, conn, lord, vassal_conn, vassal)

      # Playtest issue 340c1ad4: production stewardship is now opt-in —
      # the owner must grant it before ANY eligible steward may set
      # their production, empire-wide.
      :ok = Game.set_allow_steward_production(world, vassal, true)

      go_offline(vassal_play_live)

      {:ok, lord_play_live, _html} = live(conn, ~p"/play/#{world.id}")

      assert has_element?(lord_play_live, "[data-test='steward-production-#{vassal_city.id}']")

      # The steward's own form only ever offers the ALREADY
      # research-gated catalog (Granary needs Pottery, Bronze Spearman
      # needs Bronze Working + Copper — neither is unlocked on a
      # freshly founded vassal) filtered through `Stewardship.
      # constructive_item?/1` — never a blank check.
      form_html =
        lord_play_live
        |> element("[data-test='steward-production-#{vassal_city.id}']")
        |> render()

      assert form_html =~ ~s(value="settler")
      assert form_html =~ ~s(value="worker")
      assert form_html =~ ~s(value="warrior")
      refute form_html =~ ~s(value="granary")
      refute form_html =~ ~s(value="bronze_spearman")

      [city_before] =
        for c <- Fixtures.player_cities(world, vassal), c.id == vassal_city.id, do: c

      assert city_before.queue == []

      lord_play_live
      |> element("[data-test='steward-production-#{vassal_city.id}']")
      |> render_submit(%{"item" => "warrior"})

      [city_now] = for c <- Fixtures.player_cities(world, vassal), c.id == vassal_city.id, do: c
      assert city_now.queue != [], "the steward's click-through build order never landed"
      assert hd(city_now.queue).type == :warrior

      refute render(lord_play_live) =~ ~s(data-test="steward-error")
    end

    test "the production-stewardship form disappears once the vassal is back online", %{
      conn: conn,
      user: lord,
      other_conn: vassal_conn,
      other_user: vassal,
      world: world
    } do
      %{vassal_play_live: vassal_play_live, vassal_city: vassal_city} =
        subjugate(world, conn, lord, vassal_conn, vassal)

      go_offline(vassal_play_live)

      {:ok, lord_play_live, _html} = live(conn, ~p"/play/#{world.id}")
      assert has_element?(lord_play_live, "[data-test='steward-production-#{vassal_city.id}']")

      {:ok, _vassal_play_live_again, _html} = live(vassal_conn, ~p"/play/#{world.id}")

      {:ok, lord_play_live2, _html} = live(conn, ~p"/play/#{world.id}")
      refute has_element?(lord_play_live2, "[data-test='steward-production-#{vassal_city.id}']")
    end
  end

  describe "emergency defend — vassals panel (QA issue bd93cc0a)" do
    test "no defend affordance while the offline vassal is safe; a real click issues the order once they're struck, never sabotage",
         %{conn: conn, user: lord, other_conn: vassal_conn, other_user: vassal, world: world} do
      %{vassal_play_live: vassal_play_live} = subjugate(world, conn, lord, vassal_conn, vassal)

      go_offline(vassal_play_live)

      {:ok, lord_play_live, _html} = live(conn, ~p"/play/#{world.id}")

      [vassal_lord | _] = for u <- Fixtures.player_units(world, vassal), u.type == :lord, do: u

      refute has_element?(lord_play_live, "[data-test='steward-defend-#{vassal.id}']")

      land? = fn t -> Fixtures.tile_class(world, t) == :land end

      [barbarian_target | _] =
        world |> Fixtures.adjacent_tiles(vassal_lord.tile_id) |> Enum.filter(land?)

      barbarian = Fixtures.spawn_barbarian(world, barbarian_target)
      {:ok, _result} = Fixtures.resolve_barbarian_attack(world, barbarian.id, vassal_lord.id)

      [vassal_lord_now] =
        for u <- Fixtures.player_units(world, vassal), u.id == vassal_lord.id, do: u

      assert vassal_lord_now.hp < vassal_lord.hp,
             "setup's own barbarian strike never actually landed"

      assert vassal_lord_now.hp > 0,
             "setup's own barbarian strike killed the Lord outright — nothing left to defend"

      safe_target = adjacent_land_tile(world, vassal_lord_now.tile_id, [barbarian_target])

      {:ok, lord_play_live2, _html} = live(conn, ~p"/play/#{world.id}")

      assert has_element?(lord_play_live2, "[data-test='steward-defend-#{vassal.id}']")

      lord_play_live2
      |> element("[data-test='steward-defend-#{vassal_lord.id}-#{safe_target}']")
      |> render_click()

      Enum.reduce_while(1..10, :ok, fn _, :ok ->
        [unit_now] =
          for u <- Fixtures.player_units(world, vassal), u.id == vassal_lord.id, do: u

        if unit_now.tile_id == safe_target do
          {:halt, :ok}
        else
          Fixtures.advance_turn(world)
          {:cont, :ok}
        end
      end)

      [unit_now] = for u <- Fixtures.player_units(world, vassal), u.id == vassal_lord.id, do: u

      assert unit_now.tile_id == safe_target,
             "the real click-through defend order never actually moved the vassal's Lord"

      # QA issue bd93cc0a's own bug fix: a real DOM button's
      # `phx-value-to_tile` arrives as a STRING — before the `parse_id/1`
      # fix, `Stewardship.defend_target_allowed?/3`'s own `to_tile in
      # adjacent_tile_ids` could never match an integer list, so this
      # exact click would have misfired as provable sabotage and dinged
      # the steward's own Honor. It stays untouched.
      assert Game.honor(world, lord) == 100
    end
  end

  describe "production stewardship — alliance panel (QA issue bd93cc0a)" do
    test "an ally steward sets an offline ally's production from the constructive whitelist", %{
      conn: conn,
      user: user_a,
      other_conn: other_conn,
      other_user: user_b,
      world: world
    } do
      {:ok, join_live_b, _html} = live(other_conn, ~p"/play")

      join_live_b
      |> element("[data-test='join-world-#{world.id}']")
      |> render_click()

      {:ok, pre_play_live_b, _html} = live(other_conn, ~p"/play/#{world.id}")
      city_b = found_city(pre_play_live_b, world, user_b)

      # `Presence`'s own `:duplicate` Registry keys mean ANY live
      # connection counts as "online" (`establish_accepted_alliance/5`'s
      # own moduledoc note) — this pre-alliance mount (only used to
      # found the city) must be closed out before it, or user_b would
      # stay "online" forever regardless of the `go_offline/1` below.
      go_offline(pre_play_live_b)

      %{play_live_a: play_live_a, play_live_b: play_live_b} =
        establish_accepted_alliance(world, conn, user_a, other_conn, user_b)

      # Playtest issue 340c1ad4: opt-in, empire-wide grant — the ally
      # must turn it on before their own steward may set production.
      :ok = Game.set_allow_steward_production(world, user_b, true)

      go_offline(play_live_b)

      {:ok, play_live_a2, _html} = live(conn, ~p"/play/#{world.id}")

      # The Alliances dropdown starts collapsed (`AlliancePanel`'s own
      # `open?` default) — `alliance_row` markup, including the new
      # steward controls, only renders once it's toggled open.
      play_live_a2
      |> element("[data-test='alliance-button']")
      |> render_click()

      assert has_element?(play_live_a2, "[data-test='steward-production-#{city_b.id}']")

      play_live_a2
      |> element("[data-test='steward-production-#{city_b.id}']")
      |> render_submit(%{"item" => "worker"})

      [city_now] = for c <- Fixtures.player_cities(world, user_b), c.id == city_b.id, do: c
      assert city_now.queue != [], "the ally steward's click-through build order never landed"
      assert hd(city_now.queue).type == :worker

      _ = play_live_a
    end

    test "no steward view is ever carried for a merely-proposed (not yet accepted) alliance", %{
      conn: conn,
      user: user_a,
      other_conn: other_conn,
      other_user: user_b,
      world: world
    } do
      {:ok, join_live_a, _html} = live(conn, ~p"/play")

      join_live_a
      |> element("[data-test='join-world-#{world.id}']")
      |> render_click()

      {:ok, join_live_b, _html} = live(other_conn, ~p"/play")

      join_live_b
      |> element("[data-test='join-world-#{world.id}']")
      |> render_click()

      {:ok, play_live_b, _html} = live(other_conn, ~p"/play/#{world.id}")
      _city_b = found_city(play_live_b, world, user_b)

      go_offline(play_live_b)

      # Discovery (story 899) gates `AlliancePanel`'s own proposable
      # roster, not `Game.propose_alliance/3` itself — driving the
      # command directly here keeps this check scoped to
      # `format_alliance/3`'s own `steward` field, without needing a
      # full mutual-discovery scouting boundary just to prove a
      # `:proposed` row never carries one.
      :ok = Game.propose_alliance(world, user_a, user_b)

      [alliance] = Game.alliances(world, user_a)
      assert alliance.status == :proposed
      assert alliance.steward == nil
    end
  end

  describe "empire-wide steward-production toggle (playtest issue 340c1ad4)" do
    test "renders unchecked by default and a real click grants it — the CALLER's own flag only",
         %{conn: conn, user: user, other_conn: other_conn, other_user: other_user, world: world} do
      {:ok, join_live, _html} = live(conn, ~p"/play")

      join_live
      |> element("[data-test='join-world-#{world.id}']")
      |> render_click()

      {:ok, join_live_other, _html} = live(other_conn, ~p"/play")

      join_live_other
      |> element("[data-test='join-world-#{world.id}']")
      |> render_click()

      {:ok, play_live, _html} = live(conn, ~p"/play/#{world.id}")

      refute Game.allow_steward_production(world, user)

      refute has_element?(
               play_live,
               "[data-test='allow-steward-production-toggle'][checked]"
             )

      play_live
      |> element("[data-test='allow-steward-production-toggle']")
      |> render_click()

      assert Game.allow_steward_production(world, user)

      assert has_element?(
               play_live,
               "[data-test='allow-steward-production-toggle'][checked]"
             )

      # A second, unrelated player's own connection never sees THIS
      # player's grant on remount — the command sets only the caller's
      # own flag, empire-wide is about cities, never about other players.
      {:ok, other_play_live, _html} = live(other_conn, ~p"/play/#{world.id}")
      refute Game.allow_steward_production(world, other_user)

      refute has_element?(
               other_play_live,
               "[data-test='allow-steward-production-toggle'][checked]"
             )

      # A fresh click sends the toggle back off.
      play_live
      |> element("[data-test='allow-steward-production-toggle']")
      |> render_click()

      refute Game.allow_steward_production(world, user)
    end
  end
end
