# Broken Oaths — Feudal Vassalage: Cornerstone Design

The signature feature of Broken Oaths. Synthesises the prior-art research
(`feudal_vassalage_prior_art.md`) and the novel-design research
(`feudal_vassalage_novel_design.md`) with the product owner's locked decisions
(design session 2026-07-18). This is the reference for Three Amigos, specs, and
implementation of the feudal batch(es).

## The one-line pitch

When you take a player's **last city**, you do not eliminate them — they swear a
(broken-able) **oath of fealty** and keep playing as your **vassal**: still
building, still scheming, paying **tribute** in gold and **levies**, while they
and their fellow vassals plot **coordinated rebellions** to break free. Lords and
vassals are all **real humans**, so the drama is genuinely social and emergent.

## Why this is rare (research finding)

Almost no game keeps a *defeated human* playing under the victor — 4X games
eliminate; CK3/EU4/Total War model the subordinate as AI. The only human analogs
(Travian, EVE nullsec renting) are cautionary tales with one loud lesson:
**keeping the loser in-world only retains them if the deal is net-positive.**
Pure farming/"zeroing" the loser produces huge quit rates. Therefore the whole
design is retention-first: the vassal must always have agency, hope, and
interesting decisions, and vassalage must not *always* be negative.

## Design pillars

1. **The negotiation is the feature, not the debuff.** A vassal is a co-author of
   a political drama starting from behind — never a corpse.
2. **Persistent & endless.** There is NO world-victory / no game-over. "Win paths"
   are personal, ongoing ambitions, not a game-ender. The world runs forever.
3. **Reciprocal oaths.** The bond is two-way: the vassal owes tribute/levies/
   deference; the **lord owes protection, a share of spoils, and autonomy**.
   Neglect is what fuels rebellion. Being a lord OR a vassal can be genuinely good.
4. **Engine-enforced with Honor at stake.** Oaths are real contracts the engine
   tracks. Breaking one is *allowed* but publicly brands you: **Honor** is a
   world-visible reputation that changes how future conquests swear in. Tyrant =
   powerful but brittle; generous/honorable = stable but slow. The game is called
   *Broken Oaths* — breaking one must have systemic teeth.
5. **Rebellion is a coordinated set-piece,** not a lone dice roll — plotted among
   humans, timed, climactic.

## Locked decisions (product owner, 2026-07-18)

| Fork | Decision |
|---|---|
| Bond nature | **Reciprocal oath** — two-way obligations; lord neglect → liberty pressure |
| Tribute | **Gold + military levies** |
| Vassal agency | **Scheme toward rebellion** — but lordship/vassalage must not *always* be negative (net-positive deals exist) |
| Rebellion feel | **Coordinated set-piece** — chat-plotted, timed, loyalty-history-weighted |
| Hidden Agenda | **Yes** — secret personal win-condition chosen at the Oath screen on capture |
| Vassal victory | **Win *paths* yes, but no game-victory** — the world is endless; ambitions are ongoing |
| Oath enforcement | **Engine-enforced with Honor stakes** |
| World scale | **Both by world size** — small = 1-on-1 duels, large = multi-vassal empires & mass conspiracy. Player capacity likely **>10** (see Scale) |
| Occupied city control | **Owner runs it, lord skims** in peacetime — *but control likely shifts during wartime/revolt* (design below) |
| Capture flow | **Siege & grind, Civ-style — cities are tough** (multi-turn, HP + counterattacks) |
| Levies | **Call to arms** — lord requests, vassal must answer or eat Oath Strain + Honor loss |

## System model

### A. Capture (Story 906 — Unit Attacks City) — THIS BATCH
- First PvP in the game (Stone Age excluded it). A military unit/lord adjacent to
  a hostile **player** city can attack it.
- **Siege, Civ-style, cities are tough.** City defensive strength = base
  (20 + 5·size) + garrison bonus (895). City has HP; assaults chip it over
  **multiple turns**; the city counter-attacks the attacker. Relief is possible —
  the owner or an ally can break the siege. (Tuning: cities should feel *hard* to
  take, so conquest is a campaign, not a click.)
- At 0 HP → **capture**. The city becomes **occupied**: original owner keeps it on
  their roster; the captor controls the tribute/levy relationship and the
  last-free-city check fires (→ 907).
- Three Amigos to decide: exact capture moment (0 HP alone vs. move-a-unit-in),
  fate of the captured garrison, what happens to in-progress production, whether
  razing exists, and how "occupied" renders on the globe.

### B. Vassalization (Story 907 — Automatic Vassalization) — THIS BATCH
- When a capture leaves the defeated player with **no free (non-occupied) cities**,
  they become the captor's **vassal**.
- **Oath screen ("Terms of Oath")**: on the moment of subjugation the vassal
  secretly picks a **Hidden Agenda** — a personal ongoing ambition (e.g. *Restore*
  my realm / *Usurp* my lord / *Kingmaker* / *Merchant Prince*). Reframes defeat as
  a new game. (The agenda system's depth may phase in; the schema should carry it
  from day one.)
- Creates the **Vassalage relationship** (player → player) with, from the start,
  fields for: tribute rate (default 25%), **Oath Strain / liberty pressure** (0-100),
  **Honor** ledger hooks, agenda, and the reciprocal **contract** terms (what the
  lord owes). Even if strain/rebellion is a *later* batch, the schema must
  anticipate it so it isn't rebuilt.
- Both players notified; vassal shows "Sworn to X", lord gains a **Vassals** list.
- Vassal keeps playing fully (move, build, grow, research).

### C. Tribute + Levies (Story 908 — Tribute Payments) — THIS BATCH
- **Gold tribute**: each turn, `tribute = vassal gold income × rate` transfers
  vassal→lord; both see a **gold log** entry. Insufficient gold → debt (negative
  balance allowed). Default rate 25% (per source); the *adjust-rate* lever is a
  later story (§7.3). Greed must be self-limiting (see Anti-snowball).
- **Levies — call to arms**: the lord issues a call; the vassal must send units to
  the lord's war or **refuse**. Refusal spikes **Oath Strain** and dings the Honor
  ledger (a publicly-legible broken obligation). Vassal retains command of their
  army but owes the service. A refused call is first-class drama.
- Runs inside the per-world turn pipeline (874), alongside production/combat/barbarians.

### D. Reciprocity — the lord's half of the oath (design; mostly LATER batches)
- **Protection Pact**: the lord's binding duty to defend the vassal. Failing to
  answer when the vassal is attacked is a *broken oath* — Honor hit, realm-wide
  loyalty bleed. This is the novel half that makes it a relationship.
- Lord may also owe: a **share of spoils**, **granted autonomy** (lower tribute /
  self-rule), **shared vision**, **investment**.
- **Oath Strain (0-100)**, an EU4-liberty-desire reshaping tuned for real-time:
  rises from imbalance/neglect (unhonored protection = big spike), falls from
  investment & shared enemies. Two RT-tuned differences: (1) **slow & sticky**
  (moves over hours, so chat can operate), (2) it **gates possibility, not action**
  — high strain only means "the powder is dry"; a human still lights the spark.

### E. Rebellion — the set-piece (design; the NEXT batch, §8)
- **Pact of Broken Oaths**: a Neptune's-Pride hidden-commit conspiracy — plotters
  secretly commit to a synchronized strike turn hours out, revealed simultaneously;
  the terror is whether the sworn actually show. **Informing is first-class** — an
  invitee can sell the plot to the lord (the informer's dilemma).
- **Inspectable city-flip math** (CK3 collective-strength logic): flip odds combine
  Oath Strain + committed strength + surprise + grudges + a **superlinear**
  coordination bonus + a "trusted-striker" one-shot (never-rebelled loyalty banks a
  surprise bonus), minus the lord's response and Honor. Months of relationship
  *are* the dice — no hidden-RNG feel.
- **Lord-death Cascade**: killing a lord releases every vassal into simultaneous
  revolt — empires can dissolve in a night. Lords must keep vassals *happy*, not
  just pinned.
- **Lord counter-play**: sees conspiracy *heat* (not content), can spy/audit at an
  Honor cost, or make pre-emptive concessions — turning the plotting window into a
  negotiation generosity can still win.

### F. Wartime control of occupied cities (design nuance the PO flagged)
- Peacetime: **owner runs the occupied city, lord skims** tribute.
- Wartime / active revolt: control likely shifts — options to resolve in Three
  Amigos: during a lord-called war the lord may draw levies/production from it;
  during an open rebellion the occupied city becomes **contested** (neither fully
  controls until it flips or is re-secured). Keep the peacetime/wartime split
  explicit so the vassal's day-to-day agency survives peace but conquest still bites.

## Anti-snowball / anti-grief (research: the failure mode that kills these games)
- **Greed is self-limiting** (CK3 vassal-cap analog): holding many vassals should
  *reduce* per-vassal extraction and *raise* aggregate Oath Strain, so infinite
  snowballing decays. A vassal is "worth more alive than smashed."
- **Honor brake**: tyranny works but makes every future vassal swear in warier and
  rebel readier; generosity is a genuinely competitive strategy (a committed
  balance target, not lip service).
- **No farming the loser**: a vassal always retains their city, economy, and a live
  agenda; being a vassal must be survivable and interesting, or they quit.
- **Geographic escape valve** (Civ VI loyalty analog, optional): vassals bordering
  free/rebel realms feel outward pressure; vassals encircled by the lord stay pinned
  — geography, not just anger, shapes who can break free.

## Scale & architecture note (flagged for a later look)
- Globe frequency 54 ≈ **29,162 tiles**; regions are ~250 hexes (877). Depending on
  land fraction, a world plausibly seats **dozens** of players, not 5-10 — which is
  what makes multi-vassal empires and mass conspiracies real. This wants an explicit
  world-capacity / region-count pass, and the vassalage + tribute + turn-pipeline
  systems must be written to scale to many concurrent relationships per world.

## What ships in THIS (foundation) batch vs later
- **This batch (906/907/908):** PvP siege capture + occupation; the last-free-city
  vassalization trigger + the Vassalage relationship schema (carrying the
  forward-looking fields: agenda, oath strain, honor, contract terms) + the Oath
  screen with Hidden Agenda selection; gold tribute + call-to-arms levies through
  the turn pipeline; the Vassals/Sworn-to UI; the gold log.
- **Next batch (§8 + §7.3/7.4):** Oath Strain accrual, the Protection Pact &
  reciprocity, the Pact-of-Broken-Oaths conspiracy, city-flip math, lord-death
  cascade, adjust-tribute-rate, voluntary vassalization, Honor as full reputation.

## Round-4 final foundation mechanics (product owner, 2026-07-18)

- **Capture moment:** zeroing city HP breaks it; the attacker must then **move a
  unit onto the city tile** to occupy (Civ-style). No range-flip; you commit and
  hold a body.
- **Fallen garrison:** the **conqueror chooses** — execute the defenders or let them
  flee — and the choice carries a **small Honor consequence** (mercy is the
  honorable option; putting them to the sword costs Honor). A humane conqueror
  builds the reputation that makes future vassals swear in willingly.
- **Tribute rate is a LORD-SET, per-vassal, adjustable lever — not a fixed 25%.**
  This is the core happiness/retention dial: a high cut = more income but rising
  Oath Strain; a low cut = a contented, stable vassal. (This deliberately pulls the
  "adjust tribute rate" mechanic, §7.3, *into* the foundation because the rate is a
  day-one lever.) Default starting rate ~25%; applied to the vassal's **gross
  per-turn gold income** unless tuned otherwise. The lord sets and changes it from
  the Vassals panel; the vassal sees the rate and feels the pressure.
- **Hidden Agenda v1 = all four:** Restore, Usurp, Kingmaker, Merchant Prince.

## Round-5 decisions + build defaults (2026-07-18, post-Three-Amigos)

Product-owner answers to the implementation-blocking questions:
- **Tribute basis:** a % of the vassal's **city yields, before upkeep** (not all-gold,
  not net). Excludes one-off loot and tribute the vassal itself receives — no
  tribute-chain double-dip in v1.
- **Call to arms = pledge a SHARE of standing army for the WAR'S DURATION.** The
  vassal commits a portion of their army to the lord's war until it ends; pulling
  out early counts as **refusal** (Oath Strain spike + Honor ding). Vassal keeps
  command of the pledged units. (Chosen over the muster-point-by-deadline model.)
- **Tribute debt:** accrues; negative balance allowed; **no auto-penalty**. Being in
  the red **blocks the vassal's own spending until repaid**, and the lord simply
  goes unpaid — a natural incentive for the lord to keep the rate fair. Drama stays
  social (no seizure in v1).

Build defaults chosen to unblock implementation (documented, correctable):
- **No razing in the foundation** — capture occupies only; razing is deferred (it is
  anti-vassalage and not needed for the core loop).
- **In-progress production on capture:** the occupied city keeps running under its
  **owner** (peacetime rule), so its production queue simply continues; the lord
  skims tribute and does NOT seize production.
- **Honor deltas are small and tunable** — e.g. executing a fallen garrison ≈ −2
  Honor, releasing ≈ 0 (neutral); refusing a call / breaking protection is a larger
  hit. Exact numbers are a balancing pass, not a blocker.
- **Occupied rendering:** the city shows an "occupied / Sworn to X" marker on the
  globe and in the owner's/lord's city lists — a spec-time visual detail.
- **Wartime control override is DEFERRED to the rebellion batch.** The foundation
  always applies the peacetime rule (owner runs the occupied city). The wartime/
  revolt shift-of-control is designed with §8.
- **"Free city" = a city you own that no other player occupies.** Vassalization fires
  at **zero** free cities. Multiple last-cities falling in one tick resolve in
  **deterministic capture order**, each firing its own last-free-city check.
- **Vassalage relationship schema (to finalize at architecture/spec):**
  `{world_id, lord_player_id, vassal_player_id, tribute_rate (default 0.25),
  oath_strain (0-100, default 0), hidden_agenda (enum: restore|usurp|kingmaker|
  merchant_prince), contract_terms (jsonb — reciprocal duties, forward-looking),
  status, honor hooks}`. Built this batch carrying the forward-looking fields so the
  rebellion batch doesn't rebuild it.

## Engagement layer — Gold Bank + Feudal Stewardship (stories 909, 910)

Added 2026-07-18. Turns the persistent-world "everyone is offline sometimes" reality
into an engagement + retention loop AND a concrete *benefit* of being in a household.

### Gold Bank (909)
- Gold has a **capped bank** = the bank's size. Offline earnings accrue into the bank
  up to the cap, then **stop** (no loss, just idle waste until collected) — the reason
  to return or be tended.
- **Logged in → gold flows to the usable treasury**; **offline → accrues into the
  capped bank**. **Collect** = a click that sweeps bank → treasury (a deliberate
  engagement tap; an always-bank/always-collect variant is acceptable tuning if we
  want the tap every session).
- **Upgrade the bank** to raise the cap (costs gold/production) — a real economy
  decision; bigger bank = more offline earnings retained.

### Feudal Stewardship (910) — the upside of vassalage
- **Who stewards whom:** a player's **lord + fellow vassals of the same lord** can
  steward them **while offline**. **Lords are never stewarded by vassals** (protection
  flows down, not up).
- **Bank collection:** a steward sweeps the offline player's bank — **all to the
  owner** (pure stewardship; steward gets nothing; tribute still skims separately).
  Keeps an absent player's economy from capping out.
- **Production stewardship:** a steward may set the offline player's production queue,
  **constructive-only** (a safe whitelist of economic/defensive builds) — no
  disbanding, no cancel-griefing, no nonsense.
- **Emergency defense:** normally stewards cannot move the offline player's units; but
  **if that player is under attack**, a steward may command their units to **defend**
  — defensive orders only, active only while under attack, never to launch aggression
  or march the army off. Stops absent players from being farmed; the Protection theme
  made concrete.
- **Anti-sabotage:** every steward action is **logged** for the owner to review on
  return; provable sabotage **dings the steward's Honor** (engine-enforced).
  Constructive-only + Honor stakes keep stewardship a benefit, not a grief vector.

### Placement
909 (Gold Bank) is a near-independent economy story and a prerequisite for 910. 910
(Feudal Stewardship) depends on 907 (the lord/vassal relationship), 909 (the bank), and
the production-queue (879) / unit-combat (891) systems. Both extend the feudal
foundation batch.

## Sources
See `feudal_vassalage_prior_art.md` (CK3/EU4/Civ VI/Travian/EVE mechanics + numbers)
and `feudal_vassalage_novel_design.md` (Neptune's Pride, Nemesis, EVE heists,
ranked novel mechanics, full open-questions list).
