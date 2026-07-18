defmodule BrokenOathsSpex.Story900.Criterion7606Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7606 — selecting a known player opens the thread: clicking
  a contact in the known-players list swaps in that conversation's
  thread (messages + composer), not just a static list.

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "selecting a known player opens the thread" do
    scenario "clicking a contact opens their conversation thread" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "the player has the chat panel open", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        play_live
        |> element("[data-test='chat-button']")
        |> render_click()

        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "the player selects the discovered contact", context do
        context.play_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "that contact's conversation thread opens with an empty history and a composer",
            context do
        assert has_element?(context.play_live, "[data-test='chat-thread']")
        assert has_element?(context.play_live, "[data-test='chat-messages']")
        assert has_element?(context.play_live, "[data-test='chat-form']")
        assert has_element?(context.play_live, "[data-test='chat-input']")
        {:ok, context}
      end
    end
  end
end
