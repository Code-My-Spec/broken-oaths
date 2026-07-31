# Broken Oaths: a development retrospective

## What it is

Broken Oaths is a massively multiplayer 4X strategy game built in Elixir and Phoenix LiveView.
Players settle a hex globe that keeps turning while they sleep. The mechanic it takes its name from
is what happens when you lose: you do not die, your conqueror makes you a vassal. You pay tribute,
fight their wars, bank gold, and plot rebellion.

Underneath it is a server-authoritative simulation: a Goldberg polyhedron mesh from seeded 3D
Perlin noise, rendered through LiveView with a baked-texture canvas layer, driven by a per-world
GenServer, specified by 279 executable BDD spec files. It was built by one person, John Davenport,
using CodeMySpec, an AI harness running product interviews, Three Amigos sessions, architecture
design, spec generation, code writing and QA.

## The real shape of the build

The first commit is dated March 19, 2026 and the last is July 25. Citing that four-month span would
be dishonest. 253 of the 271 commits, 93 percent, landed in July, and 12 of the 15 distinct commit
days in the whole history are in July. Broken Oaths is a 12-day sprint with a four-month exploratory
prologue. The peak day, July 13, carried 44 commits.

Those 12 days produced 108,734 lines of Elixir across 184 modules and 443 script files, and ran 52
stories, 387 acceptance criteria, 285 BDD rules, 171 components, 55 QA attempts and 227 subagents
through the harness, shipping seven tagged releases.

## Phase 1: the prologue that was not a project (March 19 to July 11)

The whole foundation landed in a single evening. On March 19 a Phoenix 1.8 application went up with
authentication already wired (`2269035`, 68 files, 7,547 lines), and hours later a Worlds bounded
context stood on it (`d5810f1`): seeded 2D Perlin noise, flat-top axial hex coordinates with
cylindrical wrapping, a generator classifying eight terrain types from elevation against moisture.
Nine minutes later the tests arrived, 885 lines plus a status doc listing honestly what it could not
compile to verify (`e8da327`).

The sprint kept exactly one decision from that evening: the deterministic noise and hex math became
the base of the globe, while the DOM-div rendering did not survive. Then silence, and a June
market-discovery detour with no game code, swept out on July 13 (`c8b13e9`). Four months, 18
commits, one evening of game engineering, and the right primitives.

## Phase 2: the renderer loses four times (July 12 to 13)

Fifty-two commits in forty-eight hours, and the first gives away the method. `98b17c3` banked four
research documents on hexasphere geometry and rendering feasibility and repaired pre-existing test
breakage before a line of new geometry existed. Then, in twenty minutes flat, the whole spherical
substrate went in bottom-up, from 3D Perlin noise through a Goldberg mesh builder to the flat hex
view replaced by a server-rendered globe (`936b815`). Five minutes later `8081f8d` deleted the flat
world, taking 583 lines and two test files with it.

July 13 was one long argument with the renderer, and the globe lost the same fight four times. An
experimental CSS-3D mode hit 60fps using nothing but HTML divs (`2bdb96f`). Divs did not scale. The
next eight hours are a retreat conducted in good order: level-of-detail swapping at the disc edge
(`2493342`), coarser far zoom with no hit-testing while dragging (`6c6409c`), windowing the fine
layer around the view center (`3ddbd93`), a baked-texture canvas impostor for far zoom with the
coarse hexes deleted (`2190451`), and finally `885f330`, "impostor-first board, vector-canvas near
mode, zero DOM tiles." The doctrine was written down a minute later
(`c108d03`). The scars: `90b024d` versioned the `persistent_term` cache keys and `cde726e` spent
over an hour on freezes from a "hook/LiveView ownership war." `7ba5459` is the epitaph: "phones
stop drowning in hex divs." Sequencing was risk-first: the unproven renderer got the day, the known
platform got an evening.

## Phase 3: the loop turns, twice a day (July 14 to 18)

July 14 is the day Broken Oaths became a game, and it ran the full harness lifecycle twice. In the
ten minutes between 11:17 and 11:27, 37 red BDD spec files went in covering regions, world picking,
turn ticks, movement and fog of war. Implementation followed in one uninterrupted hour, ending with
a 605-line WorldServer that turned all 37 green at 12:53 (`b4cacca`). Nearly every spec file was
touched again in that commit, the sound of an API discovering its real shape. Roughly 13,000 lines
of Elixir in a day.

July 16 and 17 added enemies and then company. Four commits laid down roughly 7,900 lines of red
specs covering combat, camp cadence, city defense, garrisons and the lord before one line of combat
code existed; it arrived at 18:13 (`96c62ce`). The 17th closed with `2543e04`, 148 files and 10,131
insertions, the largest commit of the sprint: player discovery, per-world chat, alliances,
cooperative combat with bounty split by damage dealt, and a `dev_qa_controller` so the QA agent
could drive the game.

July 18 turned a prototype into a versioned product: four tagged releases in nineteen hours, opening
with v0.2.0, the Stone Age MVP, at 09:17 (`3576d60`). Then the release tax: four user-reported bugs
forced v0.2.1 at 12:49, and playtest triage cleared thirteen issues in seventy minutes. Its
midmorning produced no code, only five commits layering `feudal_vassalage_design.md`, then
`9bcc11e`: 5,624 insertions across 69 files, 46 of them executable specs and two implementation.
Sieges, vassalization, tribute, banking and stewardship were fully specified before a line of siege
logic existed.

## Phase 4: the walls come down (July 19 to 20)

Fifty-nine commits in forty-six hours, the densest stretch of the sprint. It opened mid-firefight at
1am: Copper had gone unreachable in production and broken the Bronze Spearman, so `7467b58` rewrote
resource placement and shipped as v0.2.4. By 09:12 Feudal Vassalage was live as v0.3.0, and v0.3.1
followed within the hour.

Then `6f7dc27` landed the rebellion foundation: 59 files, 9,284 insertions, three migrations, and
roughly forty spec files covering Oath Strain, Protection Pacts and the Pact of Broken Oaths. The
mechanics went live one story at a time. All of it went into `world_server.ex`, and that was the
problem.

At 18:37 a knowledge doc on GenServer decomposition became a plan, and the next ten hours are the
most consequential architectural work in the project. Eight slices pulled WorldServer apart,
starting with 1,162 lines of feudal and rebellion logic under the banner "pragdave logic-home"
(`33b2497`), then combat, cities, unit orders, social and vision, stewardship, `turn.ex` split into
domain-owned tick phases (`c6fd8b5` cut it from 1,199 lines), and the 1,161-line `game.ex` facade
split into per-domain sub-facades (`6f7f0af`).

From 23:37 to 00:58, six more commits promoted ten bounded contexts out of `Game.*` entirely: Vision,
Technology, Players, Cities, Units, Combat, Diplomacy, Feudal, Simulation. Pure moves, zero net
change. At 04:10 the LiveViews followed, `play.ex` shedding 2,028 lines into extracted components and
a view-model (`2ca18a3`).

## Phase 5: one enormous day, then the quiet (July 21 to 25)

Twenty-one of the final twenty-five commits landed on July 21, from 00:13 to 21:57. `1bd44bb`
inverted the simulation clock so movement resolved every tick and economy every tenth. Between 09:02
and 13:09 the game acquired most of its genre furniture: archer strength split into melee and ranged
with the combat resolver, camps, siege and city defense rewritten together (`15efd86`), then wonders,
buildings, chop orders and the Scout. Roughly 4,000 lines in four hours, all with tests.

Then the volume falls off a cliff. July 24 produced one correction: the world picker had been booting
a `WorldServer` just to list worlds (`6c431f7`).

## The failures, with receipts

**Weather shipped and was pulled in five minutes.** A drifting cloud layer landed at 20:31 on
July 13 (`db1d41a`) and grew storm cells and lightning by 21:00, committed as "about to be rolled
back, kept for history" (`b1bb51d`). `b8947b5` removed 249 lines at 21:05. Weather returned at
23:36 as an airspace layer of cloud hexes on the same mesh, one shell up (`580c8c6`), the lesson
the rollback paid for.

**A passing QA sweep killed the feature it blessed.** QA briefs for stories 874, 875 and 876 were
filed at 16:15 on July 14 with screenshot evidence and a clean sweep (`050bfc8`). Fourteen minutes
later the turn model was torn out (`fbba3a9`): orders now execute immediately and the turn boundary
only recharges movement, replacing the lockstep simultaneous resolution built that morning. Four
spec files were rewritten, and their filenames still read
`..._boundary_then_everything_moves_at_once_spex.exs`. Seeing the correct thing in a browser told
him it was the wrong thing.

**Specs anchored to turn counts, four separate times.** Nine city-loop specs were re-anchored to
events rather than fixed turn counts on July 16 (`62534c3`), and the lesson was relearned in
`fcb3cb9`, `08d2f1a` and `0514ef7`. "After turn 6" was fragile. "When the camp is struck" was not.

**Cross-story QA found what every per-story pass missed.** Batch 5 shipped 147 files and 8,050
insertions at 04:49 on July 18 with story-level QA already green (`ae2d940`). Four end-to-end
journeys run as a real player immediately found three bugs, and the screenshots are the receipt:
`j2_05_BUG_city_unreachable.png` and `j3_09_BUG_over_cap_worked_tiles.png` in `e0f7c40`. Fixed,
rerun 4/4 clean (`b409d27`), then frozen into regression tests (`5587e30`).

**A placeholder cost a 39-file rewrite of same-day specs.** Tribute and banking were built against
placeholder income. Wiring them to real city gold yields meant touching 39 files and rewriting
nineteen spec files authored that morning (`1dea523`). The specs held the shape; the stub underneath
did not.

**Things that took three tries.** Barbarian camp placement had to stop stealing claimed tiles
(`cff466e`), then obey an 8-15 hex band (`7f47931`), then hold its spawn counter at cap so kills
bought a three-turn grace (`0c355f0`). Copper was fixed twice, in production at 1am (`7467b58`)
and again to make access mine-based and player-wide (`495d3ca`). The feedback widget was a
three-act mess: mounted where LiveView never rendered it (`a4bcbf2`), simplified onto a deploy key
(`b12b842`), then deleted and replaced with a generated support widget (`53a4f3c`), leaving dead
references crashing `/play` until 14:45 (`2128561`).

**And the QA numbers themselves.** 55 attempts: 32 pass, 19 partial, 4 fail, so only 58 percent
passed first look. Every story that was tested did end green, 32 final attempts and 32 passes. The
problem is the denominator: 20 of the 52 stories have no QA attempt on record, and 0 of the 387
acceptance criteria are marked `verified`. The sprint shipped to production seven times with 38
percent of its stories carrying no formal QA record and not one criterion checked off. The least
flattering fact here, and the one most worth publishing.

The honest qualifier, which is not an excuse: those stories were not untested, they were tested by
people instead of by the harness. The game was live in production from July 18 with real playtesters
filing issues through the feedback widget, and roughly twenty commits exist because of what they
found. Human play caught things no per-story QA pass would have, exactly as the cross-story journeys
did. What is missing is the record, not the testing. The harness cannot tell the difference between
"nobody checked this" and "twelve people played it for a week," and on this build that distinction
is the whole story.

## Human and machine

In the main build conversation John typed 58,535 characters against 4,933,904 the machine wrote. That
is 1.17 percent, across 206 genuine human messages. Counting all 227 subagents, the machine total is
23,284,503 characters and the human share is 0.25 percent. Thinking tokens register as zero here, so
the machine total is understated.

The Cleaner CRM build ran 0.4 percent in the main conversation and 0.07 percent all-in. Broken Oaths'
human share is roughly three times higher, and the reason is not that the harness performed worse.
It is that this is the one John actually wanted for himself. He had been planning this game for
years. He wrote the persona as a description of his own taste, then said plainly what he was doing:
"This is what I am and how I've designed the game. I want to hop on the browser and play for a while
and collaborate." Somebody who intends to play the thing gives more notes than somebody shipping a
CRM. Read that percentage as a measure of how much he cared, not how much the harness needed.

You can see where the characters went in the commits they produced. `e0ceda9` retuned resource
density behind a spec titled "the world no longer feels like resources everywhere." `23f4046` eases
the globe camera to its target instead of snapping. `509064d` scoped detail degradation to touch
pans only, because the machine's fix had made capable machines worse. `8aa867b` closed "the three
open PM calls" on Scout garrison, disband and chop yield, three product decisions deliberately
deferred to the human and then collected in one pass.

Those are taste and product judgment, not code. The human input clusters on "not buttery yet," on
whether a world feels right, on which of two defensible mechanics this game wants. The machine wrote
the Goldberg mesh, the combat resolver, the ten bounded contexts and 279 spec files.

### The third input: real players

A meaningful share of those human characters were not John's opinions at all. They were other
people's. On July 20 at 21:41 he wrote "Let's do the bugs. I should probably focus on getting users
to play test," and an hour later he was recruiting: "hey, I want you to go and play my game and play
tested a little bit and use the feedback widget on the lower right to report any issues you find."

That opened a third channel into the build, and the commit log shows it working. Roughly twenty
commits reference playtest or user-reported issues. `f578c18` fixed four user-reported gameplay
issues and forced v0.2.1 out at 12:49 on July 18. Playtest triage then split three ways in seventy
minutes: backend (`bb7a0c4`), frontend (`62509c2`), mobile rendering (`883ea9f`). `a3a3bb8` records
nine playtest fixes in a single prod patch. Individual reports got tracked by id, and the transcripts
name them: "playtest issue 2a9df843" became the player display-name feature (`ca82749`).

There is a small irony worth keeping. The feedback widget that took three tries to get working on
July 17 is the pipe all of that arrived through two days later.

One caveat: `git log --format=%an` reports 255 John and 16 Claude, but that is git config on an
agent-driven repository, not a human-effort signal.

## What the build exposed about the harness

**The harness could not file its own bugs.** `create_issue` was broken by a deploy key, so nine
framework issues were banked in a markdown file instead (`9f0f151`, July 13 at 23:10). The next
morning John filed two more complaints against the architecture design run that had just generated
his component specs (`e1700d8`), a habit of critiquing the tool while riding it.

**QA rules were written after they cost an afternoon.** No `mix` invocations during QA sessions
(`10c7e8f`). Kill the dev server by port, never by process pattern (`1482e0e`). One-line rules that
exist because their absence burned time.

**Story-level QA passing did not prevent cross-story bugs.** Per-story QA is the harness's default
unit of verification, and it went green on a 147-file batch with three reachable bugs in it. John's
fix was to run end-to-end journeys as a player and codify them as regression tests, but the harness
did not ask him to. It let a clean story sweep look like a clean build.

**The record-keeping does not close the loop.** All 52 stories still sit at `in_progress` in the
CLI database, as do Cleaner CRM's 21, and zero of 387 acceptance criteria are marked `verified`
even for the 32 stories whose QA passed. Nothing marks a story done when its QA passes and its
code ships, so the harness cannot answer "what is finished" from its own records. It also never
noticed that 20 stories went untested, because it never asked.

**And the case-study tooling papered over exactly that.** The script that exports these records
for publication, `extract-stories-fixture.py`, hard-coded three fields rather than deriving them:
`status: :completed` on every story, `verified: true` on every criterion, `qa.final: :pass` on every
QA block. Run unmodified against Broken Oaths it would have published 52 completed stories, 387
verified criteria and a clean sweep, all three false. The script now reads them from the database.
The shipped MetricFlow, Market My Spec and Cleaner CRM pages predate that fix.

The uncomfortable version: a harness whose pitch is verified intent built the page that reports on
itself, and the reporting layer was the least honest part of the stack.

## Where it actually stands

Broken Oaths shipped to production seven times in eight days, through v0.3.1 with Feudal Vassalage
live and playtesters in it.

The sprint proper ended on July 25 with two commits at 12:14: easing the globe camera to its target
and adding `/dev/qa/worlds/:id/reload` to rehydrate a world from the database. Those are demo-prep,
the things you build the day before showing someone the game.

It did not stop there. On July 30 the repository took four more commits between 09:47 and 10:21,
merging a `demo/smooth-camera-and-qa-reload` branch: display names instead of internal player numbers
on units (`37c84c2`), breaking an alliance back to plain peace (`6313a67`), and cycling selection
through a stacked tile plus showing an enemy city's HP (`534a992`). That is 275 commits total, and
the character of them is unchanged from the sprint: small, player-facing, the kind of thing you fix
because you watched somebody hit it.

So the accurate statement is that Broken Oaths is a live, playable, production 4X built in a 12-day
sprint and still being worked on. What is unfinished is real and worth naming: 52 stories still open
in the harness, no acceptance criteria formally verified, and a tech tree that stops well short of
the intergalactic powers the landing page promises. This is a long-standing passion project in
mid-flight, not a finished product and not an abandoned one.

The immediate ask is playtesters on the vassalization mechanic, which is the part the game is named
after and the part that most needs other people's hands on it. Past that, the build keeps moving for
a structural reason: Broken Oaths is the most complicated thing CodeMySpec has produced, so it is
also the harness's test bed. Every revision to the harness needs something real to run against, and
this is the something real. The case study does not close because the project does not close. That
is the arrangement, and it is worth stating plainly rather than dressing a passion project up as a
finished deliverable.
