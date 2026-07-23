defmodule BrokenOaths.Feudal.StewardProductionGateTest do
  @moduledoc """
  Playtest issue 340c1ad4 — the owner-controlled, EMPIRE-WIDE toggle
  gating whether an eligible steward may set the owner's production
  (`Players.Player.allow_steward_production`, opt-in, default
  `false`). Before this gate existed, ANY eligible steward
  (`Stewardship.eligible?/1`) could always set an offline owner's
  production from the constructive whitelist with no owner-side switch
  at all — this proves the new default-closed baseline, the owner's
  own opt-in command (`Game.set_allow_steward_production/3`), and that
  ONE grant covers every city the owner has, never a single one.

  Exercises the real command surface directly against a real
  lord/vassal relationship (`SharedGivens.subjugate/5`) — same "bare
  `Game`-call, no LiveView click-through needed for the backend gate
  itself" posture `BrokenOaths.Game.FeudalFlagTest` already
  establishes; `BrokenOathsWeb.GameLive.StewardUiTest`'s own new
  toggle test covers the click-through half (the checkbox rendering
  and firing).
  """

  # async: false — mounts real `GameLive.Play` LiveViews (`subjugate/5`
  # drives the actual siege/capture flow) sharing one `WorldServer`,
  # same status every other stewardship-flow test in this suite
  # (`StewardUiTest`/`FeudalCaptureUITest`) already carries.
  use BrokenOathsTest.ConnCase, async: false

  import BrokenOathsSpex.SharedGivens

  alias BrokenOaths.Game
  alias BrokenOaths.Simulation.WorldServer
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions
  alias BrokenOathsSpex.Fixtures

  setup :register_and_log_in_user

  setup %{conn: conn} do
    other_user = UsersFixtures.user_fixture()
    other_conn = log_in_user(build_conn(), other_user)

    {:ok,
     conn: conn,
     world: Fixtures.world_fixture(%{seed: 424_242}),
     other_user: other_user,
     other_conn: other_conn}
  end

  # `SharedGivens.subjugate/5`'s own `found_far_city/3` sibling — spawns
  # a fresh Settler directly (test-only seam, same status
  # `WorldServerTest.found_far_city/3` already has) and founds a SECOND
  # city on the first land tile that clears `Production.validate_founding/3`'s
  # own minimum-spacing check against every city already on the board,
  # proving the empire-wide grant covers a city founded AFTER
  # subjugation too, not just the one the lord captured.
  defp found_second_city(world, user, player_id) do
    Enum.find_value(0..641, fn tile ->
      if Regions.tile_class(world, tile) == :land do
        settler = Game.spawn_unit_for_test(world, player_id, :settler, tile)

        case Game.found_city(world, user, settler.id) do
          :ok ->
            Game.player_cities(world, user) |> Enum.find(&(&1.tile_id == tile)) |> Map.fetch!(:id)

          {:error, _} ->
            nil
        end
      end
    end)
  end

  describe "queue_production/5's own new gate, with the grant OFF (default)" do
    test "an otherwise-eligible steward is refused with :steward_production_disabled", %{
      conn: conn,
      user: lord,
      other_conn: vassal_conn,
      other_user: vassal,
      world: world
    } do
      %{vassal_city: vassal_city, vassal_play_live: vassal_play_live} =
        subjugate(world, conn, lord, vassal_conn, vassal)

      refute Game.allow_steward_production(world, vassal)

      go_offline(vassal_play_live)

      assert Game.steward_queue_production(world, lord, vassal.id, vassal_city.id, "warrior") ==
               {:error, :steward_production_disabled}

      [city_now] = for c <- Game.player_cities(world, vassal), c.id == vassal_city.id, do: c
      assert city_now.queue == [], "the steward's build order landed despite the grant being off"

      WorldServer.restart(world)
    end
  end

  describe "queue_production/5's own new gate, with the grant ON" do
    test "the owner's own grant lets an eligible steward queue production", %{
      conn: conn,
      user: lord,
      other_conn: vassal_conn,
      other_user: vassal,
      world: world
    } do
      %{vassal_city: vassal_city, vassal_play_live: vassal_play_live} =
        subjugate(world, conn, lord, vassal_conn, vassal)

      assert Game.set_allow_steward_production(world, vassal, true) == :ok
      assert Game.allow_steward_production(world, vassal)

      go_offline(vassal_play_live)

      assert Game.steward_queue_production(world, lord, vassal.id, vassal_city.id, "warrior") ==
               :ok

      [city_now] = for c <- Game.player_cities(world, vassal), c.id == vassal_city.id, do: c
      assert city_now.queue != [], "the steward's whitelisted build order never landed"
      assert hd(city_now.queue).type == :warrior

      WorldServer.restart(world)
    end

    test "ONE grant covers EVERY city the owner has — never a per-city switch", %{
      conn: conn,
      user: lord,
      other_conn: vassal_conn,
      other_user: vassal,
      world: world
    } do
      %{vassal_city: first_city, vassal_play_live: vassal_play_live} =
        subjugate(world, conn, lord, vassal_conn, vassal)

      # A SECOND city, founded AFTER subjugation — the grant below is
      # set once, covering both, with no second grant call anywhere.
      # `player_id` (needed by `Game.spawn_unit_for_test/4`) reads off
      # the vassal's own still-standing Lord unit — their Settler was
      # already consumed founding `first_city`.
      [vassal_lord | _] =
        for u <- Fixtures.player_units(world, vassal), u.type == :lord, do: u

      second_city_id = found_second_city(world, vassal, vassal_lord.player_id)
      assert second_city_id, "setup's own second-city founding never landed"

      assert Game.set_allow_steward_production(world, vassal, true) == :ok

      go_offline(vassal_play_live)

      assert Game.steward_queue_production(world, lord, vassal.id, first_city.id, "warrior") ==
               :ok

      assert Game.steward_queue_production(world, lord, vassal.id, second_city_id, "worker") ==
               :ok

      [city_a] = for c <- Game.player_cities(world, vassal), c.id == first_city.id, do: c
      [city_b] = for c <- Game.player_cities(world, vassal), c.id == second_city_id, do: c

      assert hd(city_a.queue).type == :warrior
      assert hd(city_b.queue).type == :worker

      WorldServer.restart(world)
    end
  end

  describe "set_allow_steward_production/3 — owner-only" do
    test "sets only the CALLER's own flag, never anyone else's", %{
      user: lord,
      other_user: vassal,
      world: world
    } do
      {:ok, _lord_player} = Game.join_world(world, lord)
      {:ok, _vassal_player} = Game.join_world(world, vassal)

      refute Game.allow_steward_production(world, lord)
      refute Game.allow_steward_production(world, vassal)

      assert Game.set_allow_steward_production(world, lord, true) == :ok

      assert Game.allow_steward_production(world, lord)
      refute Game.allow_steward_production(world, vassal),
             "setting the caller's own flag leaked onto another player's row"

      WorldServer.restart(world)
    end

    test "a player who hasn't joined the world is refused", %{world: world} do
      stranger = UsersFixtures.user_fixture()

      assert Game.set_allow_steward_production(world, stranger, true) ==
               {:error, :not_a_player}

      WorldServer.restart(world)
    end
  end
end
