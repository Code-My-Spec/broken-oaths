defmodule BrokenOathsSpex.Story900.Criterion7608Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7608 — history loads on open: reopening a conversation (a
  fresh mount, as if the player navigated away and came back) shows
  the messages already exchanged, not an empty thread — chat history
  persists past a single LiveView connection.

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "history loads on open" do
    scenario "reopening a conversation shows the prior messages" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "the player already exchanged messages with their contact", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        play_live
        |> element("[data-test='chat-button']")
        |> render_click()

        play_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        play_live
        |> form("[data-test='chat-form']", message: %{body: "Shall we clear that camp together?"})
        |> render_submit()

        play_live
        |> form("[data-test='chat-form']", message: %{body: "Meet at the eastern ridge"})
        |> render_submit()

        {:ok, context}
      end

      when_ "the player reopens the conversation from a fresh session", context do
        {:ok, fresh_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        fresh_live
        |> element("[data-test='chat-button']")
        |> render_click()

        fresh_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        {:ok, Map.put(context, :fresh_live, fresh_live)}
      end

      then_ "both prior messages are shown in the reopened thread", context do
        html = render(context.fresh_live)
        assert html =~ "Shall we clear that camp together?"
        assert html =~ "Meet at the eastern ridge"
        {:ok, context}
      end
    end
  end
end
