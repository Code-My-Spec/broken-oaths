defmodule BrokenOathsSpex.Story916.Criterion7737Spex do
  @moduledoc """
  Story 916 — Coordinated Rebellion (Pact of Broken Oaths)
  Criterion 7737 — "A vassal opens a Pact of Broken Oaths as a private
  chat and invites fellow vassals of the same lord into it — membership
  of the pact chat IS the conspiracy roster... only fellow vassals of
  the same lord are eligible to be invited"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2 —
  first-class Rebellion, Pact-in-chat").

  `BrokenOaths.Game.RebellionPact` doesn't exist yet (`grep -rn
  RebellionPact lib/` comes back empty), nor does any pact-chat
  affordance anywhere in `GameLive.Play`
  (`grep -rn pact_chat lib/` is equally empty). This file (and its four
  siblings — 7738/7739/7741/7742) invent the entire surface below,
  modeled directly on this codebase's own two closest existing
  precedents — `GameLive.ChatPanel` (a toggled panel over a real-time
  message thread, story 900) and `GameLive.AlliancePanel` (a toggled
  panel with a "propose to an eligible candidate" list, story 901) —
  since the design explicitly calls the pact "bound to a CHAT" whose
  "membership IS the conspiracy roster."

  ## CANONICAL assumed surface contract (referenced by every sibling)

  Events — fired via `attempt_event/3` (no `handle_event/3` clause
  exists for any of these yet):

    * `"open_pact_chat"` — fired on the INITIATOR's own `GameLive.Play`,
      `%{"strike_turn" => turn_number_as_string, "invitee_user_ids" =>
      [id, ...]}`. Creates the pact-bound chat and invites the given
      fellow vassals of the SAME lord. A non-fellow-vassal invitee is
      silently dropped (never invited) rather than rejecting the whole
      call — see this file's own second `then_` below.
    * `"pact_commit"` / `"pact_decline"` — fired on a MEMBER's own
      mount, `%{}` (no id needed — a vassal is assumed to belong to at
      MOST one active pact at a time, a scoping judgment call this
      moduledoc flags explicitly since the design text never states
      it).
    * `"pact_inform"` — fired on an INVITED member's own mount, `%{}`,
      secretly tips the lord off (criterion 7741).
    * `"toggle_pact_panel"` — opens/closes the composer panel that
      lists invite candidates (mirrors `"toggle_alliance_panel"`/
      `"toggle_chat"`).

  `data-test` selectors (all invented, none exist today):

    * `"pact-button"` / `"pact-panel"` — the toggle + panel container,
      rendered on a VASSAL's own `GameLive.Play` only (mirrors
      `alliance-button`/`chat-button`).
    * `"fellow-vassal-\#{user_id}"` — a candidate row inside the
      composer, one per fellow vassal of the SAME lord (excludes self,
      the lord, and any non-fellow-vassal).
    * `"pact-chat"` — the private chat panel itself, visible on every
      MEMBER's own view (including the initiator) once the pact
      exists.
    * `"pact-invite-notice"` — shown on an INVITED member's own view
      before they've responded.
    * `"pact-commit"` / `"pact-decline"` — response controls, inside
      both the invite notice and the ongoing `"pact-chat"`.
    * `"pact-member-status-\#{user_id}"` — a fellow member's status as
      SEEN BY the reader; MUST read "Outstanding" for every member
      other than the reader's own row, pre-strike (criterion 7738's own
      subject).
    * `"rebellion-status"` — appears on a MEMBER's own view once their
      independence has been declared (post-strike).
    * `"pact-informed-banner"` — appears on the LORD's own view once
      any member has informed (criterion 7741).
    * `"informer-reward"` — appears on the INFORMER's own view.
    * `"brace-defenses"` / `"reposition-lord"` / `"buy-off-conspirators"`
      — the lord's pre-emption actions, available once informed.
    * `"conspiracy-heat"` — an aggregate gauge on the LORD's own view
      (criterion 7742).

  ## Judgment calls / ambiguities flagged for the Three Amigos

  1. **Strike turn representation.** The gherkin says "strike turn 50
     (about 2 hours out)". This spec passes the literal `"50"` and, in
     the sibling that actually processes a strike (7739), treats it as
     RELATIVE ("50 turn boundaries from when the pact was formed"), not
     an absolute world-turn number — subjugating three vassals via
     `subjugate/5` alone burns many dozens of real turn boundaries
     before a pact is ever opened, so "turn 50" as an ABSOLUTE counter
     value would already be in the past by the time any pact exists.
     Whichever the real implementation picks is a build-time decision;
     this spec's own turn-advancing logic only needs to be internally
     consistent with itself.
  2. **At-most-one-active-pact-per-vassal.** Assumed so `"pact_commit"`/
     `"pact_decline"`/`"pact_inform"` don't need an id param this spec
     has no legal way to read back (a `then_` may not call context
     functions or read `Repo` to fetch a freshly-created pact's own
     id). Never stated explicitly in the design; flagged here rather
     than invented silently.
  3. **Eligibility test shape.** The gherkin's own When only names
     inviting Ada and Bo; this criterion's second Then ("only fellow
     vassals... are eligible") is tested by re-opening the composer
     (`"toggle_pact_panel"`) after the fact and reading its candidate
     list, rather than by attempting to invite the outsider directly —
     the latter would need a way to observe a REJECTED invite without
     any sanctioned read of an id-scoped pact state.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Wes opens a pact chat and invites two fellow vassals into it",
    fail_on_error_logs: false do
    scenario "Wes opens a pact chat and invites two fellow vassals into it" do
      given_ "a world with room for five players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 12}))}
      end

      given_(:registered_player)
      given_(:three_vassals_of_one_lord)

      given_ "a fourth player exists in the world who is NOT one of Mira's vassals", context do
        outsider_user = Fixtures.user_fixture()

        outsider_conn =
          Phoenix.ConnTest.build_conn()
          |> BrokenOathsTest.ConnCase.log_in_user(outsider_user)

        {:ok, join_live, _html} = live(outsider_conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, Map.put(context, :outsider, %{user: outsider_user, conn: outsider_conn})}
      end

      when_ "Wes opens a Pact of Broken Oaths chat naming strike turn 50 and invites Ada and Bo into it",
            context do
        [wes, ada, bo] = context.pact_vassals

        {:ok, wes_live, _html} = live(wes.conn, "/play/#{context.world.id}")

        attempt_event(wes_live, "open_pact_chat", %{
          "strike_turn" => "50",
          "invitee_user_ids" => [to_string(ada.user.id), to_string(bo.user.id)]
        })

        {:ok, context |> Map.put(:wes, wes) |> Map.put(:ada, ada) |> Map.put(:bo, bo)}
      end

      then_ "Ada and Bo each join the pact chat and can commit or decline in secret", context do
        {:ok, ada_live, _html} = live(context.ada.conn, "/play/#{context.world.id}")
        {:ok, bo_live, _html} = live(context.bo.conn, "/play/#{context.world.id}")

        assert has_element?(ada_live, "[data-test='pact-invite-notice']"),
               "expected Ada to see an outstanding pact invite on her own view"

        assert has_element?(ada_live, "[data-test='pact-commit']")
        assert has_element?(ada_live, "[data-test='pact-decline']")

        assert has_element?(bo_live, "[data-test='pact-invite-notice']"),
               "expected Bo to see an outstanding pact invite on his own view"

        assert has_element?(bo_live, "[data-test='pact-commit']")
        assert has_element?(bo_live, "[data-test='pact-decline']")

        {:ok, context}
      end

      then_ "only fellow vassals of the same lord (Mira) are eligible to be invited into the chat",
            context do
        {:ok, wes_live2, _html} = live(context.wes.conn, "/play/#{context.world.id}")

        attempt_event(wes_live2, "toggle_pact_panel", %{})

        assert has_element?(wes_live2, "[data-test='fellow-vassal-#{context.ada.user.id}']"),
               "Ada, a fellow vassal of Mira, should be an eligible invite candidate"

        assert has_element?(wes_live2, "[data-test='fellow-vassal-#{context.bo.user.id}']"),
               "Bo, a fellow vassal of Mira, should be an eligible invite candidate"

        refute has_element?(wes_live2, "[data-test='fellow-vassal-#{context.outsider.user.id}']"),
               "an outsider who is not one of Mira's vassals must never be an eligible candidate"

        refute has_element?(wes_live2, "[data-test='fellow-vassal-#{context.user.id}']"),
               "the lord herself is not a FELLOW vassal and must never be an eligible candidate"

        {:ok, context}
      end
    end
  end
end
