defmodule BrokenOathsSpex.Story873.Criterion7440Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7440 — an abandoned region carries no traces to its next owner.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an abandoned region is a fresh start for its next claimant" do
    scenario "the next claimant inherits nothing" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the first player joined, then abandoned their region", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        region = Fixtures.claimed_region(context.world, context.user)

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        play_live
        |> element("[data-test='abandon-world']")
        |> render_click()

        play_live
        |> element("[data-test='abandon-confirm']")
        |> render_click()

        {:ok, Map.put(context, :abandoned_region, region)}
      end

      when_ "new players join until one claims the abandoned region", context do
        claimed =
          Enum.reduce_while(1..5, nil, fn _, _ ->
            user = Fixtures.user_fixture()

            conn =
              Phoenix.ConnTest.build_conn()
              |> BrokenOathsTest.ConnCase.log_in_user(user)

            {:ok, join_live, _html} = live(conn, ~p"/play")

            join_live
            |> element("[data-test='join-world-#{context.world.id}']")
            |> render_click()

            if Fixtures.claimed_region(context.world, user) == context.abandoned_region,
              do: {:halt, user},
              else: {:cont, nil}
          end)

        assert claimed, "no new player was placed in the abandoned region"
        {:ok, Map.put(context, :new_owner, claimed)}
      end

      then_ "the new owner has a clean spawn — two units, no leftovers", context do
        units = Fixtures.player_units(context.world, context.new_owner)
        assert length(units) == 2

        # No trace of the previous owner remains anywhere on the board
        assert Fixtures.player_units(context.world, context.user) == []
        {:ok, context}
      end
    end
  end
end
