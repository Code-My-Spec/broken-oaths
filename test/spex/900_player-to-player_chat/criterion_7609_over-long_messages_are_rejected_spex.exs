defmodule BrokenOathsSpex.Story900.Criterion7609Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7609 — over-long messages are rejected: the story caps a
  message at 500 characters ("Text only, max 500 characters per
  message"), so submitting more than that must not deliver the
  message and must surface a rejection to the sender.

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives. `[data-test='chat-error']` is this spec's
  assumed selector for the rejection notice.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "over-long messages are rejected" do
    scenario "a message over 500 characters never reaches the thread" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "the player has the conversation open", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        play_live
        |> element("[data-test='chat-button']")
        |> render_click()

        play_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "the player submits a message over 500 characters", context do
        too_long = String.duplicate("a", 501)

        context.play_live
        |> form("[data-test='chat-form']", message: %{body: too_long})
        |> render_submit()

        {:ok, Map.put(context, :too_long, too_long)}
      end

      then_ "the message is rejected, not delivered to the thread", context do
        html = render(context.play_live)
        refute html =~ context.too_long
        assert has_element?(context.play_live, "[data-test='chat-error']")
        {:ok, context}
      end
    end
  end
end
