defmodule BrokenOathsSpex.Story952.Criterion2766Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2766 — Scout completes faster than a Warrior in the same
  city: at the same flat 5 production/turn base
  (`BrokenOaths.Cities.Production`'s "flat production base" doc), a
  cheaper item (Scout 30) banks enough to complete in fewer turns than
  a costlier one (Warrior 40) queued alone in an otherwise-identical
  city.

  Compares two independently-founded, freshly-seeded cities (same
  world shape, same starting production) rather than queuing both in
  one city's queue — queuing Warrior BEHIND Scout in a single queue
  would always make it finish later regardless of relative cost (queue
  order alone would explain that), which would not isolate "cheaper
  completes faster" as its own fact. Two isolated cities, each queuing
  exactly one item type, isolate cost as the only variable.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Scout completes faster than a Warrior in an otherwise-identical city" do
    scenario "fewer turns bank the cheaper Scout than the costlier Warrior" do
      given_ "a player founds a city and queues a Scout", context do
        world = Fixtures.world_fixture(%{seed: 424_242})
        user = Fixtures.user_fixture()
        conn = Phoenix.ConnTest.build_conn() |> BrokenOathsTest.ConnCase.log_in_user(user)

        {:ok, join_live, _html} = live(conn, "/play")
        join_live |> element("[data-test='join-world-#{world.id}']") |> render_click()

        {:ok, play_live, _html} = live(conn, "/play/#{world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(world, user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(world, user)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "scout"})

        {:ok,
         context
         |> Map.put(:scout_world, world)
         |> Map.put(:scout_user, user)}
      end

      given_ "a second, independent player founds their own city and queues a Warrior", context do
        world = Fixtures.world_fixture(%{seed: 909_090})
        user = Fixtures.user_fixture()
        conn = Phoenix.ConnTest.build_conn() |> BrokenOathsTest.ConnCase.log_in_user(user)

        {:ok, join_live, _html} = live(conn, "/play")
        join_live |> element("[data-test='join-world-#{world.id}']") |> render_click()

        {:ok, play_live, _html} = live(conn, "/play/#{world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(world, user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(world, user)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        {:ok,
         context
         |> Map.put(:warrior_world, world)
         |> Map.put(:warrior_user, user)}
      end

      when_ "each world advances turn by turn until its own unit completes", context do
        scout_turns =
          turns_to_complete(context.scout_world, context.scout_user, :scout)

        warrior_turns =
          turns_to_complete(context.warrior_world, context.warrior_user, :warrior)

        {:ok,
         context
         |> Map.put(:scout_turns, scout_turns)
         |> Map.put(:warrior_turns, warrior_turns)}
      end

      then_ "the Scout banked in strictly fewer turns than the Warrior", context do
        assert context.scout_turns != nil, "the Scout never completed within the turn budget"
        assert context.warrior_turns != nil, "the Warrior never completed within the turn budget"
        assert context.scout_turns < context.warrior_turns
        {:ok, context}
      end
    end
  end

  defp turns_to_complete(world, user, unit_type, max_turns \\ 15) do
    Enum.reduce_while(1..max_turns, nil, fn turn, _ ->
      Fixtures.advance_turn(world)

      if Enum.any?(Fixtures.player_units(world, user), &(&1.type == unit_type)) do
        {:halt, turn}
      else
        {:cont, nil}
      end
    end)
  end
end
