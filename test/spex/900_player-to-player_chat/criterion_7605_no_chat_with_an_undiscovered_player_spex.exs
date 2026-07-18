defmodule BrokenOathsSpex.Story900.Criterion7605Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7605 — no chat with an undiscovered player: a third
  civilization sharing the same world, but never scouted into vision,
  must never appear as a reachable contact — chat availability tracks
  discovery (story 899), not mere world membership.

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives.

  Bespoke world: this scenario needs THREE concurrent players, but the
  shared fixture world (seed 424242, frequency 8, used by `:a_world`)
  has exactly TWO spawnable regions — a third join is geometrically
  impossible there (issue 7509b3e6, see story 879's criterion 7472).
  Seed 1 / frequency 9 deterministically yields three.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "no chat with an undiscovered player" do
    scenario "a stranger sharing the world never appears as a known contact" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "an undiscovered third player has also joined the world", context do
        {:ok, join_live, _html} = live(context.third_conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      when_ "the player opens the chat panel", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        play_live
        |> element("[data-test='chat-button']")
        |> render_click()

        {:ok, Map.put(context, :play_live, play_live)}
      end

      then_ "the discovered player is reachable but the undiscovered one is not", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}']"
               )

        refute has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.third_user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
