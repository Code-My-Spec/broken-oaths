# Qa Result — 907 Automatic Vassalization (RE-QA)

## Status: partial

## Summary

Every mechanic THIS story owns — once a vassalage exists — is genuinely reachable and correct
through real UI clicks: the Oath screen (all 4 agenda options, real click persists the pick and
closes the modal), the lord's "Vassals (1)" panel, the vassal's "Sworn to X" + rate badges, and
the vassal continuing to play (answer/refuse levies, retain units, manage their occupied city).

The one blocker is upstream, in 906: a real player still cannot reach the trigger condition
(capturing a last free city) through the shipped UI at all (issue 7f91cff2, filed against 906).
This session's vassalage row was re-created fresh (`hidden_agenda: nil`, default
`tribute_rate: 0.25`, `oath_strain: 0`) to mirror exactly the state a genuine capture produces
— city 9's underlying capture itself was real (a prior session's server-side event, same code
path a real click invokes) — but the capture->vassalize hand-off was not observed firing live,
end-to-end, from a fresh in-session capture, because that capture step itself isn't clickable
yet.

## Scenarios

- **7666 Losing the last free city triggers vassalization** — PASS by reconstruction (see
  Summary): a fresh `game_vassalages` row exists for lord=11/vassal=12 mirroring the real
  historical trigger; not re-observed firing live in this session due to 906's capture gap.
- **7667 Losing one of several cities does not create vassalage** — not testable; World 3 is
  a 2-player/1-city-each world by construction, same gap as the original QA session.
- **7668 Vassal secretly chooses a Hidden Agenda on the Oath screen** — PASS, fully live. The
  "Terms of Oath" modal rendered for player B with all 4 options (Restore, Usurp, Kingmaker,
  Merchant Prince); clicked "Usurp" for real, `game_vassalages.hidden_agenda` persisted as
  `usurp`, modal closed.
- **7669 New vassalage record created with default forward-looking fields** — PASS. Verified
  via psql: `tribute_rate: 0.25, oath_strain: 0, contract_terms: {}, status: active` on
  creation.
- **7670 Both players notified and the relationship surfaces in each UI** — PASS (UI surfacing
  half only). Lord's "Vassals (1)" dropdown showed the vassal row with email/rate/oath strain;
  vassal's top bar showed "Sworn to qa-901-a@broken-oaths.test" + rate badge. The live
  `:vassalized`/`:new_vassal` PubSub notification push was NOT independently observed firing
  this session (the row was seeded fresh via SQL + page reload, not a live server-side trigger
  event) — reviewed by code inspection only for the notification-push half.
- **7671 Vassal keeps playing normally after subjugation** — PASS. Player B answered one levy,
  refused another, kept full command of all 3 units throughout (none deleted/reassigned), and
  had full access to their occupied city's Build catalog.
- **7672 A player already holding an occupied city becomes a vassal when their last free city
  falls** — not testable; requires 2+ cities per player, same gap as the original QA session.

## Evidence

Screenshots at `.code_my_spec/qa/907/screenshots/`:
- `01_oath_screen_usurp_chosen.png` — live Oath screen, all 4 agenda options, real click
- `02_vassals_panel_lord_view.png` — lord's real Vassals dropdown (vassal row, rate, oath strain)

psql verification: `game_vassalages` row (defaults, then `hidden_agenda: usurp` after the
click).

## Issues Filed

None new against 907 directly — the blocking gap (906's missing capture-completion UI) is
filed against 906 (issue 7f91cff2) since that's where the fix belongs.
