# Rebellion demo — QA seeds that double as a walkthrough

The per-story QA journeys and the demo video want the SAME deterministic staged
states. Build them once as named, boot-into-state demo seeds + the dev controls
to walk them live in a browser (no manual setup mid-demo). The demo IS the QA
journeys stitched into a narrative.

## The four beats the demo must show (user-requested)

1. **Take over another civ and vassalize them** — stories 906 (Siege) + 907
   (Vassalization). Demo player (as LORD) has a strong unit adjacent to a rival's
   LAST city → attack → break → move in → occupy → the rival swears fealty and
   appears as a vassal. Show it live (the money shot).
2. **The vassal side of a strained lord relationship** — stories 908 (Tribute) +
   913 (Oath Strain) + 914 (Protection Pact). Show BOTH vantage points: the
   lord's vassal-row (tribute rate control, `vassal-oath-strain` badge) AND the
   vassal's own board (`my-oath-strain` gauge + drivers, tribute being paid).
   The strain gauge should read visibly HIGH so the tension is legible.
3. **The rebellion mechanic** — story 915. From the strained vassal state:
   Declare Independence → the preview (`rise-preview-city-*` will-rise/stays-loyal
   + `rebellion-army-preview`) → confirm → cities rise, the lord's garrison
   defects, a strain-sized temporary army spawns, war is declared
   (`at-war-with`, `rebellion-panel`).
4. **Win independence** — story 919. Hold the risen cities for N (=10) turns with
   no re-occupation → `rebellion-status = independence_won`, the oath permanently
   severed, the rebel free. Needs a live "advance turn" path so the win is
   reachable in a few clicks.

Optional bonus beats (available, not required): coordinated Pact of Broken Oaths
(916), lord's-death "seize the moment" + heir (917), negotiated peace (919).

## What the seeds/tooling must provide

- **A named demo world (or small set) that BOOTS INTO the staged state** — the
  spex-only seams (`set_player_honor_for_test`, tyrant setup, strain spikes) are
  test-only; a LIVE browser demo needs the world to already be in the state, via
  a seed script, not manual play. Stage:
  - a rival civ reduced to its last city, with the demo player's army adjacent
    (beat 1, one capture away);
  - the demo player ALSO a vassal under an NPC **tyrant** lord (Honor floored +
    tribute maxed → cities will rise), with Oath Strain pre-raised (beats 2–4);
  - so the demo player can show the LORD side (their new vassal) and the VASSAL
    side (their own strained oath) in one world.
- **A live "advance turn" affordance** so beat 4 (hold N turns → win) is
  walkable without waiting on the real 60s tick — a dev/demo end-turn control or
  a seed staged near the threshold.
- **A short click-by-click demo script** (`.code_my_spec/qa/rebellion_demo_script.md`,
  to be written during QA) the user follows on camera.

## Delivery note

Fold this into the per-story QA journeys (906/907 → capture+vassalize; 908/913/914
→ strained relationship; 915 → declare; 919 → win). Each journey already needs
its staged seed; make those seeds demo-grade (named, reproducible, visually
legible) and thread them so the four beats play in sequence.
