defmodule BrokenOathsSpex.Story900.Criterion7610Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7610 — unread badge tracks incoming messages: an incoming
  message raises both the chat button's total unread count and that
  contact's own count in the known-players list, live, with no
  refresh — and opening the conversation clears both (folded in from
  more_stories.md §9.2, "Chat Notifications").

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives. `[data-test='chat-badge']` (on the chat
  button) and `[data-test='unread-count-ID']` (per contact, in the
  known-players list) are this spec's assumed badge selectors.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "unread badge tracks incoming messages" do
    scenario "an incoming message raises the badge; opening the thread clears it" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "the recipient has the chat panel open on the contacts list", context do
        {:ok, recipient_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        recipient_live
        |> element("[data-test='chat-button']")
        |> render_click()

        {:ok, Map.put(context, :recipient_live, recipient_live)}
      end

      given_ "the sender has this conversation open", context do
        {:ok, sender_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        sender_live
        |> element("[data-test='chat-button']")
        |> render_click()

        sender_live
        |> element("[data-test='known-player-#{context.user.id}']")
        |> render_click()

        {:ok, Map.put(context, :sender_live, sender_live)}
      end

      when_ "the sender sends a message", context do
        context.sender_live
        |> form("[data-test='chat-form']", message: %{body: "Are you still there?"})
        |> render_submit()

        {:ok, context}
      end

      then_ "the recipient sees an unread badge, on the button and on the contact",
            context do
        assert has_element?(context.recipient_live, "[data-test='chat-badge']", "1")

        assert has_element?(
                 context.recipient_live,
                 "[data-test='unread-count-#{context.other_user.id}']",
                 "1"
               )

        {:ok, context}
      end

      when_ "the recipient opens that conversation", context do
        context.recipient_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "the badge clears", context do
        refute has_element?(context.recipient_live, "[data-test='chat-badge']")

        refute has_element?(
                 context.recipient_live,
                 "[data-test='unread-count-#{context.other_user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
