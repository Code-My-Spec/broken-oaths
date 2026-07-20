defmodule BrokenOathsSpex.Story900.Criterion7604Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7604 — chat is available with a discovered player: once a
  player has discovered another (story 899's vision-triggered
  first-contact), that player appears as a known contact behind the
  chat button, and opening it lets you reach them.

  Surface contract this spec (and its siblings under this story)
  assumes for `BrokenOathsWeb.GameLive.ChatPanel`, mounted as a child
  of `GameLive.Play` the same way `UnitPanel`/`CityPanel` are:

    * `[data-test='chat-button']` — opens the panel; carries
      `[data-test='chat-badge']` with the total unread count when > 0
    * `[data-test='chat-panel']` — the panel itself, once open
    * `[data-test='known-players-list']` containing one
      `[data-test='known-player-ID']` (ID being the other player's
      user id) per discovered player
    * `[data-test='chat-thread']` — the open conversation, once a
      known player is selected, containing `[data-test='chat-messages']`
      (each message a `[data-test='chat-message']`) and the composer:
      `[data-test='chat-form']` / `[data-test='chat-input']`
      (`message[body]`, submits on enter — mirrors the existing
      support-chat widget's composer at
      `BrokenOathsWeb.SupportWidgetLive`)

  Discovery itself (story 899, `BrokenOaths.Diplomacy.Discovery`) isn't
  implemented yet — `given_(:two_players_discovered_each_other)`
  drives the real trigger for it (a lord scouting into the other
  player's vision) rather than seeding a "known player" record, so
  this spec goes red on both the discovery half and the chat half
  until both stories land.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "chat is available with a discovered player" do
    scenario "a discovered player appears behind the chat button" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      when_ "the player opens the chat panel", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        play_live
        |> element("[data-test='chat-button']")
        |> render_click()

        {:ok, Map.put(context, :play_live, play_live)}
      end

      then_ "the discovered player is listed as a known contact", context do
        assert has_element?(context.play_live, "[data-test='chat-panel']")

        assert has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
