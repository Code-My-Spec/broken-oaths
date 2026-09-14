# QA Brief: Story 1001 - Mutual Peace Without Settlements

## Tool

web (vibium CLI, via curl-login + cookie transplant workaround for issue b35b3040)

## Auth

- Player A: qa-901-a@broken-oaths.test / qa-password-123! (player_id 11)
- Player B: qa-901-b@broken-oaths.test / qa-password-123! (player_id 12)

Login via curl (real Set-Cookie handling), then `vibium cookies "_broken_oaths_key" "<value>"` to transplant into the browser. See .code_my_spec/qa/plan.md's System Issues section for the exact recipe.

## Seeds

World 3 ("QA World (Multiplayer)", paused) already has an active war between players 11 and 12 (game_wars id=2, declarer=11). City 8 (player 11's, occupied_by_player_id=12) is a pre-existing wartime conquest to check criterion 3126 against.

## What To Test

- **Criterion 3123:** As player 11, submit the `[data-test='offer-peace-form-12']` form (button `[data-test='offer-peace']`). Confirm `game_wars.peace_offered_by_player_id` becomes 11.
- **Criterion 3124:** As player 12, confirm `[data-test='pending-peace-offer']` shows "Peace offered by" the rival, and `[data-test='accept-peace']` is present (only rendered when `peace_offered_by_user_id != current user`). Click it.
- **Criterion 3125:** Confirm `game_wars.status` becomes something other than 'active' (e.g. 'peace'/'ended') after acceptance, and both players' UI no longer shows `[data-test='at-war-with']` for each other.
- **Criterion 3126:** Confirm city 8's `occupied_by_player_id` is still 12 after peace (unchanged) -- the occupation/conquest is preserved, not reverted by the peace settlement.

## Result Path

DB-backed QA attempt via `submit_qa_result` (task_id ad6fb849-aea2-4cbc-8645-3e3e522f4533).
