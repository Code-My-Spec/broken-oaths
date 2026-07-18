# Qa Story Brief

## Tool

web (vibium browser — `BrokenOathsWeb.GameLive.ChatPanel` is a LiveComponent on the `/play/:id` LiveView board)

## Auth

Session-based magic-link login, per `.code_my_spec/qa/plan.md`. Two identities are needed to observe real-time delivery, so this session uses **sequential single-tab identity switching** (per the environment note: a prior session saw a 2nd tab's socket fail to reconnect after relogin).

For each identity:

1. `vibium go "http://localhost:4050/users/log-in"`
2. Submit `#login_form_magic` with `input[name="user[email]"]` = the identity's email (see Seeds below) — no password needed, both are pre-confirmed accounts.
3. Read the magic link from `http://localhost:4050/dev/mailbox` (Swoosh local adapter) and navigate to it to complete login.
4. Navigate to `http://localhost:4050/play/2` (world id 2, "QA World (Fill Test)").

To switch identities: log out (or clear session by navigating to `/users/log-out` if present, else re-visit `/users/log-in` which will redirect if already authenticated — log out explicitly first) then repeat steps 1-4 for the other identity.

## Seeds

No new seeds needed — reuse the existing staged pair from a prior QA session (verified via `psql broken_oaths_dev` before writing this brief):

- World id **2**, "QA World (Fill Test)" (`turn_seconds=10`)
- `qa891pvpC@test.local` — game_players.id = 4
- `qa891pvpD@test.local` — game_players.id = 3
- `game_known_players` has both directions (world_id=2): viewer 3→discovered 4, viewer 4→discovered 3 — mutual discovery confirmed, chat should be unlocked between them.
- `chat_conversations` / `chat_messages` / `chat_blocks` are all empty for this pair — clean slate, no need to reset anything.

If an undiscovered third party is needed for criterion 7605 ("no chat with an undiscovered player"), any other seeded user in a **different** world (e.g. the QA user `qa@broken-oaths.test` in World 1) works — since chat is scoped by `Game.known_players/2` per world, a user with zero known_players rows in World 2 will show an empty/absent contacts list there.

## What To Test

Drive `BrokenOathsWeb.GameLive.ChatPanel` at `/play/2` for both `qa891pvpC@test.local` and `qa891pvpD@test.local`. DOM contract: `chat-button`, `chat-badge`, `chat-panel`, `known-players-list`, `known-player-<id>`, `chat-thread`, `chat-messages`, `chat-message`, `chat-form`, `chat-input`, `chat-error`, `chat-load-older`, `block-player`, `chat-blocked-notice`, `unread-count-<id>`.

- **Chat available with a discovered player (criterion 7604):** as pvpC, open `chat-button` → `chat-panel` shows `known-players-list` containing `known-player-3` (pvpD's user id) with pvpD's email.
- **No chat with an undiscovered player (criterion 7605):** confirm the QA user (`qa@broken-oaths.test`, no known_players row with pvpC/pvpD in World 2) does NOT appear in either party's `known-players-list` in World 2. If time allows, also spot-check World 1 (different world) shows a different/empty contact set — ties into per-world scoping below.
- **Selecting opens the thread (criterion 7606):** click `known-player-<id>` → `chat-thread` renders with `chat-messages`, `chat-form`, `chat-input`, `block-player`.
- **Real-time delivery (criterion 7607):** as pvpC, send a message via `chat-input` + enter/submit on `chat-form`. Screenshot pvpC's view showing the sent `chat-message`. Then log out, log in as pvpD, navigate to `/play/2`, open chat, select pvpC's contact row — confirm the message appears (already delivered/persisted; note whether the `chat-badge`/`unread-count-3` shows unread on pvpD's panel *before* opening, which is the real-time-delivery-to-inbox signal even under sequential-tab constraints). Send a reply from pvpD, then switch back to pvpC and confirm it arrives.
- **History loads on open (criterion 7608):** after a few messages exist, reopen `chat-thread` for that contact — recent messages appear with sender attribution (own vs. other) and are visible in `chat-messages`.
- **Over-long messages rejected (criterion 7609):** submit a message body over 500 characters via `chat-input`. Expect a `chat-error` and no new `chat-message` added. **Known DB-schema risk to specifically verify:** `Chat.Message.changeset/2` validates `max: 500`, but the `chat_messages.body` migration column is `:string` (Postgres `varchar(255)`) — a body between 256-500 chars passes Ecto validation but may fail at the DB with a truncation error. Test one message in the 256-500 range (e.g. 300 chars) in addition to a >500 char message, and watch for a crash/500 vs. a clean `chat-error`.
- **Unread badge (criterion 7610):** while pvpD's chat panel is CLOSED, have pvpC send a new message; reload/re-render pvpD's session and confirm `chat-badge` (total) and `unread-count-4` (per-contact, pvpC's user id) appear before opening, and both clear after opening `chat-panel` and selecting that contact.
- **Older messages page in on demand (criterion 7619):** send enough messages in one conversation to exceed the 50-message recent window (or reason about `chat-load-older` behavior on a smaller set if 50+ isn't practical in the session time budget — at minimum verify `chat-load-older` is present once any messages exist and clicking it doesn't error and does not duplicate messages already shown).
- **Chat is per-world (criterion 7620):** confirm pvpC's `known-players-list` in World 2 doesn't leak into another world's board (e.g. World 1) — a fresh identity or the QA user in World 1 should not see pvpC/pvpD as contacts, and any conversation state stays scoped to `world_id=2` (verify via `psql broken_oaths_dev` — `chat_conversations.world_id`).
- **Profanity filtered before delivery (criterion 7621):** send a message containing a banned word (e.g. "shit", "fuck") from `BrokenOaths.Chat.Moderation`'s list — confirm the delivered/persisted `chat-message` shows asterisks masking the word (`****`), not the raw word, on BOTH sender's and recipient's view. Cross-check via `psql broken_oaths_dev` (`chat_messages.body`) that the masked form, not the raw form, was persisted.
- **Blocking mutes both directions (criterion 7622):** as pvpC, click `block-player` on pvpD's thread — confirm pvpC's own composer (`chat-form`) is replaced by `chat-blocked-notice`. Then switch to pvpD: confirm pvpD's `chat-form` composer is STILL present per the component's documented asymmetric-UI design (only the blocker's UI shows `chat-blocked-notice`), but a message pvpD attempts to send is silently NOT delivered (verify via `psql broken_oaths_dev` that no new `chat_messages` row lands, and/or that pvpC never sees it after switching back) — `Chat.send_message/4` returns `{:error, :blocked}` under the hood.

## Result Path

Findings are filed via `create_issue` as they're found (per workflow — no `result.md`). Evidence (screenshots, psql output) saved under `.code_my_spec/qa/900/screenshots/` and `.code_my_spec/qa/900/responses/`.

## Setup Notes

- Single shared vibium browser instance — sequential identity switching only, no parallel tabs (per environment note about socket reconnect failures).
- `vibium screenshot` always writes to `~/Pictures/Vibium/screenshot.png` — copy aside after each capture into `.code_my_spec/qa/900/screenshots/` with a descriptive name.
- Do NOT run `mix`, `iex -S mix`, `mix run`, or `mix run -e` at any point — read all DB state via `psql broken_oaths_dev`.
- If vibium hangs: `pkill -f chrome-for-testing; pkill -x vibium; rm -f ~/Library/Caches/vibium/vibium.sock`, then `vibium go` again.
