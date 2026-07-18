defmodule BrokenOathsSpex.Story900.Criterion7607Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7607 — a message arrives in real time: the recipient's
  already-open conversation shows a new message the instant it's sent,
  with no manual refresh — the same "connected view updates itself"
  contract story 874's turn broadcasts and story 895's alerts already
  prove for other PubSub-driven pushes.

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a message arrives in real time" do
    scenario "the recipient's open thread updates without a refresh" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "both players have this conversation open", context do
        {:ok, sender_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        sender_live
        |> element("[data-test='chat-button']")
        |> render_click()

        sender_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        {:ok, recipient_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        recipient_live
        |> element("[data-test='chat-button']")
        |> render_click()

        recipient_live
        |> element("[data-test='known-player-#{context.user.id}']")
        |> render_click()

        {:ok,
         context
         |> Map.put(:sender_live, sender_live)
         |> Map.put(:recipient_live, recipient_live)}
      end

      when_ "the sender submits a message", context do
        context.sender_live
        |> form("[data-test='chat-form']", message: %{body: "Barbarians massing east of me"})
        |> render_submit()

        {:ok, context}
      end

      then_ "the recipient's open thread shows it without refreshing", context do
        assert render(context.recipient_live) =~ "Barbarians massing east of me"
        {:ok, context}
      end
    end
  end
end
