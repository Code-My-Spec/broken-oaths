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
end
