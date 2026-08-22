# Rushdown Rhea

Proto-persona (PM self-identification + secondary research), researched
2026-08-21. Decision stake: Broken Oaths' timing-sensitive mechanics —
Workers chop woods/rainforest (948), Scout early recon (952), and unit
movement/pathfinding/turn resolution (953) — and how transparently the
game exposes the numbers a player needs to plan a precisely-timed play.

## Role

Experienced Civilization-series player (same genre background as
[[ledger-minded-mara]]) who chop-rushes: pre-plants workers on forest
or resource tiles so a chop's production burst can be timed to land
exactly when it's needed. This is a well-documented, named technique
in the reference genre, not an idiosyncratic habit — guides exist
specifically to teach it, and governor/policy synergies exist to
amplify it [E1, E2, E3].

## Goals

Two race conditions, not a solo optimization puzzle:

- **Beat an opponent or the AI to a contested wonder.** Chopping to
  finish a wonder before someone else claims it is a named strategy
  in the reference genre ("How to Beat AI by Rushing Wonders") [E1,
  E4].
- **Land an army push the moment new capability arrives.** Timing a
  chop or production burst to complete a unit right as a tech or
  civic unlocks it — "the timing push" is itself a named concept in
  genre strategy writing [E3, E5].

## Pain Points

None significant by her own account — she holds up Civilization's
chop system as a system that already does this well [E1]. That's
worth taking at face value rather than manufacturing a complaint: the
implication for design isn't "fix something broken," it's "match the
bar this reference system already clears." Notably, *other* players in
that same community do experience real frustration losing wonder races
to the AI — forum discussion describes it as immersion-breaking when
the AI plays purely defensively against the human rather than
pursuing wonders for its own benefit [E4]. That's the fate her
playstyle is built to avoid, not a pain point she reports having.

## Context

A race — against the AI or real opponents — not an isolated puzzle
against the game's own systems. The guide literature for this
technique is explicitly framed as counter-play: chop to beat someone
else to the finish line, not just to optimize a number in a vacuum
[E1, E4].

## Decision Drivers

"Legible" means the yield math has to be knowable in advance — enough
to answer "will this chop actually finish my unit or wonder this
turn?" before committing a worker to it. This isn't a vague ask: in
the reference game, chop yield is an exact, publicly documented
formula (base yield scales from ~20 up to ~200 as tech/civic progress
approaches 100%, i.e. it pays to hold a chop until research lands)
[E5, E6, E7] — not hidden, not randomized. A system built this way
rewards pre-planning (pre-plant the worker, time the chop to a tech
landing) over trial-and-error, which is exactly the skill expression
she's optimizing for.

## Quotes

- "I would more do it to beat out a computer player... if a computer
  player or an opponent was building a wonder that I would chop to
  get a wonder completed, or chopped to get a unit completed so that
  I could accomplish some sort of goal." [E1]
- "I wouldn't say there's any real pain points around it. Civilization
  does this pretty good." [E1]
- "It's a race against other players or an AI." [E1]
- "There needs to be some understanding of how much you got from the
  job, so you [know] whether it's gonna complete your unit or
  complete your wonder or whatever." [E1]

## Anti-Patterns

Design traps that break this persona:

- **Hidden or randomized chop/yield math.** If she can't calculate in
  advance whether a chop will finish the target, pre-planting a
  worker stops being a skill play and becomes a guess [E1, E5].
- **No way to see progress toward a target before committing the
  action.** The whole point is knowing ahead of time, not finding out
  after [E1].
- **A wonder/timing race that isn't actually contested** — e.g. the
  AI/opponent never meaningfully competes for the same target. Removes
  the race entirely, which is the goal she's actually optimizing
  around, not a side effect [E1, E4].

## Evidence

- E1: PM self-identification interview, 2026-08-21 (this project) —
  chop-rush practice, the two race-goals (wonder, timing push), no
  personal pain points, race-not-puzzle framing, and the "legible"
  definition are all primary self-report from this session.
- E2: Chop-rushing as a named, guide-documented technique with
  governor synergy (Magnus) — CivFanatics "[GS] - To chop or not to
  chop, that is the question!" and "Civ VI early game guide for the
  Decidedly Average."
- E3: Timing a chop/push to land against opponents — "On Towards the
  Stars: The Timing Push" and "On Towards the Stars: Synergies, Civ/
  Leader Abilities, and First Turn Planning" (theahura Substack
  strategy guides).
- E4: Racing the AI for wonders as a real, widely-discussed genre
  pattern — Comrade Kaine "How to Beat AI by Rushing Wonders";
  CivFanatics "When the AI consistently beats you to a wonder by 1
  turn..." and "Why Civ 6 AI is terrible - Part 1: Wonders."
- E5: Chop yield scaling with tech/civic progress, making it worth
  timing a chop against a research completion — Comrade Kaine wonder-
  rushing guide; CivFanatics "When to Chop/Harvest."
- E6: The exact, documented chop yield formula (~20 scaling to ~200 as
  tech/civic progress nears 100%) — Civilization Wiki "Production
  (Civ6)"; Steam Community "Chop Bonus" discussion.
- E7: Yield/percentage math as a genre-recognized, calculable system
  rather than a hidden one — "On Towards the Stars: Yields and
  Percentages" (theahura Substack).
