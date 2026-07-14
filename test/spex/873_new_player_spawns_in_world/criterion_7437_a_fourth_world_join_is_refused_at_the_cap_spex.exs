defmodule BrokenOathsSpex.Story873.Criterion7437Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7437 — the three-world membership cap is enforced with a clear message.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a fourth world join is refused at the cap" do
    scenario "three memberships is the ceiling" do
      given_ :registered_player

      given_ "the player already plays in three worlds", context do
        worlds =
          for seed <- [111_111, 222_222, 333_333] do
            world = Fixtures.world_fixture(%{seed: seed})
            {:ok, join_live, _html} = live(context.conn, ~p"/play")

            join_live
            |> element("[data-test='join-world-#{world.id}']")
            |> render_click()

            world
          end

        {:ok, Map.put(context, :worlds, worlds)}
      end

      given_ "a fourth world exists with room", context do
        {:ok, Map.put(context, :fourth, Fixtures.world_fixture(%{seed: 444_444}))}
      end

      when_ "they try to join the fourth world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.fourth.id}']")
        |> render_click()

        {:ok, Map.put(context, :join_live, join_live)}
      end

      then_ "the join is refused with a message about the three-world limit", context do
        assert has_element?(context.join_live, "[data-test='join-error']")
        assert render(context.join_live) =~ ~r/three/i
        assert Fixtures.claimed_region(context.fourth, context.user) == nil
        {:ok, context}
      end

      then_ "the three existing memberships are untouched", context do
        for world <- context.worlds do
          assert Fixtures.claimed_region(world, context.user) != nil
        end

        {:ok, context}
      end
    end
  end
end
