# Rebellion demo — click-by-click on-camera script

The four-beat walkthrough for the demo video (and the manual QA pass for stories
906/907, 908/913/914, 915, 919). Companion to `rebellion_demo_plan.md`. The
staged world comes from `priv/repo/qa_seeds_rebellion.exs`.

## Setup (before you hit record)

1. Bring up the dev server on port 4050 (`mix phx.server`).
2. Seed the world: `mix run priv/repo/qa_seeds_rebellion.exs`. It is idempotent
   and self-healing, so re-run it any time to reset to the canonical
   beat-1-ready state (after a rehearsal, between takes, whenever).
3. Read the printed summary block. It gives you, for THIS run: both QA logins,
   the world id, the rival's city id and your warrior's id/tile, and all the
   dev URLs. Keep it on a second monitor. Every id below refers to that block.
4. Two browser profiles (or one plus an incognito window): one logged in as the
   **demo player** (`qa-913-demo@...`), one as the **rival** (`qa-913-rival@...`),
   both password `qa-password-123!`. You drive the demo player the whole time;
   the rival window is only to show the other side if you want to.

The world boots PAUSED, so nothing drifts while you talk. Turns advance only
when you run the step control:

    curl -X POST http://localhost:4050/dev/qa/worlds/<world-id>/step

Bind that to a key or keep the command handy. It works even while paused.

## Dismiss the Oath screen first (off-camera — 907's agenda UI)

Do this BEFORE you hit record, so the video opens on the conquest and saves the
"you're a vassal too" turn for Beat 2. The seed marks the demo player's one city
as occupied by the tyrant and leaves the Hidden Agenda unpicked, so on the FIRST
board load you are greeted by the **Terms of Oath** screen
(`data-test="oath-screen"`): "Your last free city has fallen. You are sworn to
[the tyrant]." Pick a Hidden Agenda — any works, it's secret and changes nothing
downstream (this also exercises story 907's agenda-choice UI) — and the modal
closes onto the board. Now start recording.

## Beat 1 — Take over another civ and vassalize them (906 + 907)

The money shot. You are one hit from conquering the rival.

1. As the demo player, open the board (`/play/<world-id>`). Rotate to your
   warrior (the summary block gives its id and tile). It stands right next to the
   rival's one and only city.
2. Select the warrior. Attack the rival's city. It sits at 10 HP with no
   garrison, so one hit breaks it and you take zero damage back. The city drops
   to 0 HP and reads as broken.
3. Advance one turn (the step control) so the warrior's movement recharges.
4. Move the warrior onto the broken city's tile to occupy it.
5. The rival swears fealty. They appear in your **Vassals** panel, and their
   civilization keeps playing under you. Nobody got eliminated.

Talk track: losing does not end your game. Your conqueror makes you a vassal.

## Beat 2 — The vassal side of a strained lord relationship (908 + 913 + 914)

Now show both ends of a lord/vassal bond at once. You are a lord to the fresh
rival vassal, and you are a strained vassal to an NPC tyrant.

1. Still as the demo player, open the **Vassals** panel. Point out your new rival
   vassal row: the tribute-rate control and the `vassal-oath-strain` badge, low
   for now since the relationship is brand new.
2. Now flip to your OWN oath. Open your oath / feudal panel. You are the vassal of
   the NPC tyrant (`qa-913-tyrant@...`). Your `my-oath-strain` gauge reads near
   the top (90 of 100). Tribute rate is maxed at 100 percent, draining you every
   turn boundary, and the tyrant's honor is on the floor.

Talk track: treat your vassals well and they hold. This tyrant does the
opposite, and the pressure is about to break.

## Beat 3 — The rebellion mechanic (915)

1. As the demo player, open the independence preview against the tyrant (the
   oath panel's declare-independence action).
2. Show the preview: your capital reads `will_rise?: true` (the tyrant's floored
   honor plus maxed tribute guarantee it), and the `rebellion-army-preview`
   shows a strain-sized temporary army (10 units at strain 90).
3. Confirm. Your city rises, a temporary rebel army spawns, and the war is
   declared. The board shows `at-war-with` the tyrant and the `rebellion-panel`
   appears.

Talk track: a mistreated vassal does not just complain. They raise an army and
declare a war of independence.

## Beat 4 — Win independence (919)

1. Hold your risen city. Advance turns with the step control, once per real turn,
   ten times, without letting the tyrant re-occupy the city (the NPC never
   attacks in this seed, so you just count to ten).
2. Watch the `rebellion-panel` count the hold. At the tenth turn it flips to
   `rebellion-status: independence_won`.
3. The oath is permanently severed. You are free, and you kept the rival vassal
   you took in beat 1.

Talk track: hold your ground and the oath breaks for good. You walked in as
someone's property and walked out a free power with a vassal of your own.

## Optional bonus beats (staged data supports them, not required on camera)

- **916 Coordinated rebellion**: invite conspirators into a Pact of Broken Oaths
  chat, commit in secret, strike together. The seed leaves the demo player able
  to open a pact.
- **917 Lord's death, seize the moment**: kill the tyrant's Lord unit (garrisoned
  at Tyrant's Hold) to trigger the succession choice. The heir respawns after the
  war ends.
- **919 Negotiated peace**: instead of holding to victory, settle for a restored
  vassalage or full independence with optional reparations.

## Reset between takes

Re-run `mix run priv/repo/qa_seeds_rebellion.exs`. It clears any captured city,
temporary army, declared rebellion, or moved unit and puts everything back to the
beat-1-ready state, so every take starts clean.
