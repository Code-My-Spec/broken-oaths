defmodule BrokenOathsSpex.Story900.Criterion7621Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7621 — profanity is filtered before delivery:
  `BrokenOaths.Chat.Moderation` scrubs a message's text before it ever
  reaches the recipient, so the raw profanity is never rendered on the
  other end — this is a delivery-time filter, not a client-side
  display trick, so it's observed from the RECIPIENT's own view.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "profanity is filtered before delivery" do
    scenario "a profane message reaches the recipient already censored" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "the recipient has this conversation open", context do
        {:ok, recipient_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        recipient_live
        |> element("[data-test='chat-button']")
        |> render_click()

        recipient_live
        |> element("[data-test='known-player-#{context.user.id}']")
        |> render_click()

        {:ok, Map.put(context, :recipient_live, recipient_live)}
      end

      when_ "the sender sends a message containing profanity", context do
        {:ok, sender_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        sender_live
        |> element("[data-test='chat-button']")
        |> render_click()

        sender_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        sender_live
        |> form("[data-test='chat-form']", message: %{body: "you are a fucking coward"})
        |> render_submit()

        {:ok, context}
      end

      then_ "the recipient never sees the raw profanity, only a censored message", context do
        html = render(context.recipient_live)
        refute html =~ "fucking"
        assert html =~ "coward"
        {:ok, context}
      end
    end
  end
end
