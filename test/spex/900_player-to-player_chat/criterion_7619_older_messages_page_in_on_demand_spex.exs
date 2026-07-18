defmodule BrokenOathsSpex.Story900.Criterion7619Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7619 — older messages page in on demand: opening a
  conversation loads only the last 50 messages ("Chat history persists
  (loads last 50 messages per conversation)"); anything older than
  that is fetched explicitly, not dumped in all at once.

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives. `[data-test='chat-load-older']` (mirroring
  `BrokenOathsWeb.SupportWidgetLive`'s existing "Load older messages"
  button) is this spec's assumed pagination control.

  Message bodies are zero-padded ("Message number 01" .. "55") so no
  message's text is a substring of another's — a plain "Message number
  1" would also match "Message number 10".."19"/"51", making a
  `refute html =~ ...` on the oldest message meaningless.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "older messages page in on demand" do
    scenario "the oldest message only appears after paging" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "the player has sent 55 messages in this conversation", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        play_live
        |> element("[data-test='chat-button']")
        |> render_click()

        play_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        for n <- 1..55 do
          label = n |> Integer.to_string() |> String.pad_leading(2, "0")

          play_live
          |> form("[data-test='chat-form']", message: %{body: "Message number #{label}"})
          |> render_submit()
        end

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

      then_ "only the last 50 messages loaded — the oldest is missing", context do
        html = render(context.fresh_live)
        assert html =~ "Message number 55"
        refute html =~ "Message number 01"
        {:ok, context}
      end

      when_ "the player clicks to load older messages", context do
        context.fresh_live
        |> element("[data-test='chat-load-older']")
        |> render_click()

        {:ok, context}
      end

      then_ "the oldest message is now visible", context do
        assert render(context.fresh_live) =~ "Message number 01"
        {:ok, context}
      end
    end
  end
end
