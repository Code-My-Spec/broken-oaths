defmodule BrokenOathsSpex.Story901.Criterion7623Spex do
  @moduledoc """
  Story 901 — Cooperative Barbarian Fighting
  Criterion 7623 — two players who have discovered each other can plan
  a joint barbarian assault over chat: one player's proposal ("Let's
  attack barbarian camp at (50, 75) together" — the exact example
  utterance from stone_age.md §8.2) reaches the other, already-connected
  ally live, without a page refresh (stone_age.md §8.2, "chat allows
  coordination" / "players can plan coordinated attacks via chat").

  Surface note: `BrokenOathsWeb.GameLive.AlliancePanel` — this story's
  own component — is NOT where this criterion's chat UI lives. Story
  901's own description is explicit that it depends "on Player-to-Player
  Chat for the coordination channel," i.e. it REUSES story 900's real
  chat surface rather than growing a second, competing composer;
  `AlliancePanel` is presumably where cooperative-fight-specific facts
  (shared targets, split bounties) surface, not messaging. Story 900's
  own sibling specs (`BrokenOathsSpex.Story900.Criterion7604Spex` and
  `Criterion7607Spex`) already commit to a concrete
  `BrokenOathsWeb.GameLive.ChatPanel` surface contract — `chat-button`
  → `chat-panel` → `known-player-ID` → `chat-thread` (`chat-form` /
  `chat-input`, `message[body]`) — and to `given_(:two_players_
  discovered_each_other)` (`BrokenOathsSpex.SharedGivens`) as the real
  discovery precondition chat requires. This spec reuses both rather
  than inventing a duplicate `alliance-chat-*` surface that would only
  ever collide with story 900's real one once both land — the same
  "don't fabricate a second surface for a fact another story already
  owns" discipline as any other cross-story dependency.

  Structurally this mirrors story 900 criterion 7607's own "a message
  arrives in real time" scenario (both players already have the thread
  open; the sender submits; the recipient's open view updates without a
  refresh) — restated here as story 901's own acceptance criterion
  because a coordinated-attack PROPOSAL is the specific message content
  this story cares about, not chat delivery in general.

  HTML-escaping note: `render/1` returns raw markup, not a parsed DOM —
  and `ChatPanel`'s message body interpolates through ordinary HEEx
  `{...}` (correctly escaped, since a message body is untrusted player
  text — the exact same safety story 900's own `Chat.Moderation`
  profanity filter, criterion 7621, already assumes downstream). This
  scenario's own example utterance, quoted verbatim from stone_age.md
  §8.2, happens to contain an apostrophe, which safe HEEx rendering
  turns into `&#39;` in the raw markup — no other 900/901 message body
  fixture hits this (none of them contain `'`/`"`/`<`/`>`/`&`), so nothing
  else in this suite needed the same care. `html_escaped/1` below
  derives the exact expected substring the same way `Phoenix.HTML`
  itself would, rather than hardcoding the entity — matching against
  the RAW apostrophe would be matching a string this component must
  never actually produce.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  @proposal "Let's attack barbarian camp at (50, 75) together"

  spex "allies form up to coordinate" do
    scenario "a coordinated-attack proposal reaches the other, already-connected ally live" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:two_players_discovered_each_other)

      given_ "both discovered allies have their shared conversation open", context do
        {:ok, sender_live, _html} = live(context.conn, "/play/#{context.world.id}")

        sender_live
        |> element("[data-test='chat-button']")
        |> render_click()

        sender_live
        |> element("[data-test='known-player-#{context.other_user.id}']")
        |> render_click()

        {:ok, recipient_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

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

      when_ "one ally proposes a coordinated barbarian assault over chat", context do
        context.sender_live
        |> form("[data-test='chat-form']", message: %{body: @proposal})
        |> render_submit()

        {:ok, context}
      end

      then_ "the proposal appears in the proposing ally's own thread", context do
        assert render(context.sender_live) =~ html_escaped(@proposal)
        {:ok, context}
      end

      then_ "the other, already-connected ally sees the same proposal live, with no refresh",
            context do
        assert render(context.recipient_live) =~ html_escaped(@proposal)
        {:ok, context}
      end
    end
  end

  # `render/1` returns raw HTML markup, not a parsed DOM — matching
  # against untrusted text a component correctly ran through ordinary
  # (escaping) HEEx interpolation means matching against what that
  # escaping actually produces, not the original raw string. See this
  # module's own "HTML-escaping note" above.
  defp html_escaped(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
