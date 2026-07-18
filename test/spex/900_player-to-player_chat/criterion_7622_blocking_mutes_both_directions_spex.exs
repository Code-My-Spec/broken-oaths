defmodule BrokenOathsSpex.Story900.Criterion7622Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7622 — blocking mutes both directions: once a player blocks
  a contact (`BrokenOaths.Chat.Block`), neither side can deliver a
  message to the other in that conversation — not just "you can't send
  to them," but "they can't reach you either."

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives. `[data-test='block-player']` (a control in
  the open thread) and `[data-test='chat-blocked-notice']` (shown in
  place of the composer once blocked) are this spec's assumed
  block-related selectors.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "blocking mutes both directions" do
    scenario "a block silences both the blocker's and the blocked player's messages" do
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

      when_ "the player blocks that contact", context do
        context.play_live
        |> element("[data-test='block-player']")
        |> render_click()

        {:ok, context}
      end

      then_ "the composer is replaced by a blocked notice", context do
        assert has_element?(context.play_live, "[data-test='chat-blocked-notice']")
        refute has_element?(context.play_live, "[data-test='chat-form']")
        {:ok, context}
      end

      when_ "the blocked player tries to message the blocker anyway", context do
        {:ok, blocked_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        blocked_live
        |> element("[data-test='chat-button']")
        |> render_click()

        blocked_live
        |> element("[data-test='known-player-#{context.user.id}']")
        |> render_click()

        blocked_live
        |> form("[data-test='chat-form']", message: %{body: "Come on, unblock me"})
        |> render_submit()

        {:ok, context}
      end

      then_ "the blocker never receives it", context do
        refute render(context.play_live) =~ "Come on, unblock me"
        {:ok, context}
      end
    end
  end
end
