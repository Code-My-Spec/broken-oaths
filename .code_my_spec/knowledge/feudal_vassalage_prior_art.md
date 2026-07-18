# Feudal Vassalage / Subjugation / Tribute / Rebellion — Prior Art

Research for the Broken Oaths cornerstone feature: capturing a player's **last** city
makes them your **vassal** (not eliminated). They keep playing, pay tribute, and can
coordinate **rebellions** with other vassals to break free. Persistent, real-time
(60s ticks), 5-10+ concurrent HUMAN players.

The rare and hard part is the last bullet: **a defeated human keeps playing under the
victor.** Almost every game surveyed either eliminates the loser (board/4X) or models
the subordinate as AI. The MMOs that keep the loser in the world (Travian, Grepolis,
Tribal Wars, EVE renting) are the most directly relevant and also the clearest warnings
about how this goes wrong.

---

## 1. Per-game mechanic breakdowns

### Crusader Kings 3 — the gold standard for "vassals as a living threat"

Vassals are subordinate but keep acting with agency. The threat is the **faction**, not
individual grumbling. Four faction types: **independence** (break away), **dissolution**
(shatter the realm), **liberty** (lower crown authority), **claimant** (install a
different ruler).

- **Faction discontent runs off a military-power threshold.** A faction accrues
  discontent only while its combined military strength exceeds **80%** of the liege's
  power; below 80% discontent drains. Speed scales with how far past the threshold it is.
  At **100% discontent** the faction issues its ultimatum (or immediately if the liege
  unjustly imprisons a member). This is the key design move: **rebellion is gated on
  organized collective strength, not individual anger.** One angry vassal is noise; a
  coalition that outweighs you is an existential threat.
- **Opt-out valves.** A vassal cannot join a faction if it has **80+ opinion** of the
  liege, is bound by a strong hook, is in a truce/alliance, or is landless. AI vassals at
  80+ opinion auto-leave factions. So the liege can defuse a rebellion by buying off
  swing members rather than needing to please everyone.
- **Feudal contract obligations** (the tribute dial), with opinion costs:
  - Tax: Exempt 0% (+15 opinion) · Low 2.5% (+10) · Normal 10% (+5) · High 15% (−10) ·
    Massive 25% (−20).
  - Levies: Exempt 0% (+15) · Low 10% (+10) · Normal 25% (+5) · High 35% (−10) ·
    Massive 50% (−20).
  - **Raising an obligation adds +20 tyranny opinion** (doubled Normal→High tax) — but
    you can dodge the tyranny hit by spending a **hook** or lowering the other
    obligation. Squeezing costs legitimacy.
- **Crown authority** is the central tradeoff (per the ACOUP analysis): higher authority
  massively raises what vassals owe and unlocks title revocation / heir designation, but
  makes vassals actively unhappy and funnels them into liberty factions. Lower authority
  = content vassals, starved treasury. There is no free lunch; the game is the balancing.
- **Powerful vassals** (top strength holders) demand council seats: **−40 opinion** if
  excluded; **+30** if their preferred heir wins succession, **−20** if not.
- **Civil war resolution:** liege wins → imprison all members, **+20 Dread**, revoke
  titles without tyranny for a window; faction wins → ultimatum enforced, liege loses
  **−20 Dread and −20 Legitimacy**. Losing costs face, not just territory.

**Why it works:** vassals are never eliminated, always scheming; the player is
perpetually reading a threat board and deciding whom to appease, imprison, marry, or
crush. The drama is *social*, and rebellion is a *coordination* problem.

### Crusader Kings 2 — same DNA, cruder

- Factions form when vassals drop below ~50 opinion (low diplomacy, bad traits, tyranny
  from illegal imprisonments/revocations). Independence factions need same-ish
  culture/religion and to be within ~200 capital distance.
- Player gets a **"Dangerous Factions"** alert at **70%** relative strength; AI issues
  ultimatums from **~75%**, with big jumps at **100%** and **150%**.
- Executing nobles generates tyranny and needs a valid reason — being in a faction isn't
  one. Lesson: the sovereign's coercive tools are deliberately expensive.

### Europa Universalis 4 — the richest **subject-type taxonomy** and tribute plumbing

Every subject (except trade companies / tributaries) carries **liberty desire (LD)**;
LD ≥ certain thresholds enable an independence war, and you can only diplo-annex at
**LD ≤ 50%**.

- **Subject types and base LD** (dev-scaled component 0.25 LD per development):
  - Vassal: 0% base · March: **−15%** · Daimyo +10% · Appanage **+35%** · Tributary −5%.
  - **Client state: −25% permanent LD** (the "loyal by construction" subject).
- **What drives LD up:** subject development, and **combined subject army strength vs.
  your own** (if your vassals collectively out-muscle you, they get restless — same
  "relative power" logic as CK3). Royal marriage, diplo tech, relations all feed in.
- **What pulls LD down:** be stronger than them (conquer more), high **diplomatic
  reputation**, "placate ruler" (spend prestige/influence), estate privileges,
  developing their land (−2.5% LD per dev point, short-term).
- **Tribute flows:**
  - Vassal / appanage / daimyo: overlord takes a share of the subject's tax income
    monthly; merchant republics also siphon 50% trade power.
  - **March: pays no tax** but becomes a military buffer — **+30% force limit, +25%
    manpower, −20% maintenance** if it stays small (≤25% of overlord dev), and it feeds
    the overlord +20% of its force limit. The "make them a loyal soldier, not a piggy
    bank" archetype.
  - **Tributary:** keeps **full diplomatic independence** (can war, have its own
    subjects), pays yearly tribute the overlord demands — 12.5% income, or 25% manpower,
    or monarch points — **and can refuse.** Very lightweight leash.
- **Diplo-annexation:** integratable after 10 years at 100% cost (75% if "incorporated").
  Marches and tributaries can't be diplo-annexed at all.

**Design lesson:** having *multiple* subordination tiers lets the overlord choose between
extracting money, extracting soldiers, or holding a loyal buffer — and lets the subject's
experience differ (a client state feels safe, an appanage feels rebellious). Broken Oaths
could expose the *same* vassal at different "contract" settings.

### Total War (Three Kingdoms / Warhammer) — loyalty decay and betrayal

- Vassals keep autonomy and can negotiate a **guarantee of non-annexation** as a
  condition of submitting — the subordinate gets a *contractual protection*, which is why
  AI accepts vassalage when it needs a shield.
- **Loyalty is never permanent and decays over time.** Strong factions (would-be rivals)
  are never loyal forever; weak minor factions make the most reliable vassals. You must
  keep *paying* the relationship with gifts, marriages, ancillaries.
- Warhammer III makes reliability type-dependent: Chaos vassals literally cannot rebel;
  Norsca vassals can be **confederated away by a rival** — i.e., a third party can poach
  your subject. Relevant to a multi-human world: your vassal is a recruitment target.
- **Confederation** (absorbing a faction with no ongoing tribute) is the "full merge"
  endpoint versus the ongoing-tribute vassal — two distinct exits.

### Civilization VI — **Loyalty pressure and city flipping** (very relevant to "flip to break free")

Cities have Loyalty 0-100. Loyalty changes per turn from summed pressure:

- **Each citizen exerts base pressure 1**, effective within **9 tiles**, **−10% per tile**
  of distance. Nearby *your* citizens push loyalty up; nearby *enemy* citizens push down.
- **Governor in the city: +8 loyalty/turn.** Amenities: **+3** if Happy, **+6** if
  Ecstatic. A newly conquered city: **−5** occupation penalty (mitigated by a garrison).
  Golden/Heroic age: **+0.5** per citizen pressure; Dark age: **−0.5**.
- **At 0 loyalty the city revolts into a Free City** (independent, +10 loyalty to resist).
  If a Free City then hits 0, it **joins whichever civ exerted the most pressure** — so a
  city can flip to a *neighbor* purely through demographic/cultural pressure, no army.

**Design lesson:** this is a *bloodless* conquest/liberation channel. In a human MMO, a
"loyalty pressure" field around cities means a vassal near friendly (rebel) territory
naturally trends toward breaking free, while a vassal surrounded by the lord's cities
stays pinned — geography becomes politics.

### Civilization V — puppet vs annex vs raze, and city-state tribute

- **Puppet:** city is yours but self-governs (AI builds, gold-focused); **much smaller
  happiness penalty**; you can't direct it until you annex later. The "keep the asset,
  defer the cost" option.
- **Annex:** full control but a big happiness hit (raises policy/tech costs). **Raze:**
  burn it, −1 pop/turn to ruins.
- **City-state tribute:** if your army outmatches theirs and you're within 8 tiles they
  are "Afraid" and will hand over **~100 gold (+5/era)** or a worker on demand — but each
  demand costs **15 influence (50 for a worker)**, so bullying erodes the relationship.
  Coercion is a repeatable-but-costly action, not free.

### Persistent MMO strategy — the closest genre, and the cautionary tales

- **Travian (Kingdoms):** villages inside a king's borders generate **~20% of hourly
  wood/clay/iron as tribute**; the king can collect once the tribute fund hits 20%. A
  village owner can **deny tribute collection**, and the king can grant **protection**
  (can't be conquered by kingdom members while protected). Conquering uses **loyalty**:
  every village starts at 100, a "chief/senator" attack knocks loyalty down, at ≤0 it's
  conquered and resets to ~25, **regenerating +1/hour**. This is a genuine "defeated but
  still playing under a lord who taxes you" system — the tribute + protection + deny loop
  is close to the Broken Oaths concept.
- **Tribal Wars:** village loyalty 100, a Nobleman hit drops it by a random ~20-35, so
  **4-5 nobles** (a "noble train") take a village; on capture loyalty resets to **25** and
  regenerates **+1/hour**. Conquest is a repeatable grind, not instant death — but the
  loser typically just gets **farmed** afterward.
- **Grepolis / Ogame:** the developers openly document the failure mode. Losing your
  **only** city to conquest produces a **"huge"** quit rate with **low restart**. After
  rebuilding, players get **"bashed"/farmed** for battle points and resources; attackers
  *prefer* a victim who keeps producing troops. Beginner protection exists precisely
  because unprotected new players "are immediately farmed" and "abandon entire servers."
- **EVE Online nullsec renting** — real human vassalage at scale. Alliances with surplus
  sovereignty **rent** systems/moons to subordinate corps (peaked near **1 trillion ISK/mo**
  to some landlords in 2013). Renters get income + protection + autonomy; landlords get
  passive ISK and a buffer population. But: **"renters tend to have no sense of loyalty to
  their landlords,"** protection doubles as extortion (pay or we attack), and the landlord
  can **raise rent, evict, or reshape** the space at will. Structural result: **wealth
  concentration and stagnation** — the strong get stronger, mobility dies. This is the
  snowball risk in its purest human form.

---

## 2. What makes vassalage FUN vs. a chore

**Fun (drama + agency):**
- **Rebellion is a coordination game with a visible threshold** (CK3's 80% rule). Vassals
  scheme, recruit each other, and the lord watches a threat meter he can act on. The fun
  is in the *organizing*, not a dice roll.
- **The lord faces a real tradeoff** (CK3 crown authority): more extraction = more risk.
  Both squeezing and being lenient are legitimate strategies with downsides.
- **The subordinate keeps meaningful choices:** deny tribute (Travian), pick which faction
  to join, negotiate a no-annex guarantee (Total War), grow quietly toward independence
  (EU4 LD). Being a vassal is a *position to play from*, not a waiting room.
- **Multiple subordination flavors** (EU4) so the relationship isn't one flat debuff — a
  march/soldier feels different from a milked appanage.
- **Bloodless flip channels** (Civ VI loyalty) give the underdog a path to freedom that
  doesn't require out-fighting the lord who just beat them.

**Chore / pure debuff (players quit):**
- **Being farmed with no recourse** (Grepolis "bashing," Travian raiding, Lords Mobile
  "zeroed"). If vassalage is just "you now exist to be looted," the loser logs off.
- **Death spiral:** losing your only city → restart from zero → immediately farmed again.
  Documented top quit driver in Grepolis/Ogame/Travian.
- **No agency:** if the lord holds every dial and the vassal can only pay, it's a
  punishment screen. EVE renters churn because they have "no loyalty" — they're tenants,
  not stakeholders.
- **Static, un-triggerable rebellion:** if breaking free is impossible or purely
  RNG/timer, discontent isn't a game, it's a status effect.

---

## 3. Anti-patterns & exploits

- **Snowballing / rich-get-richer.** Tribute funds the lord's army, which conquers more
  vassals, which fund more army. EVE renting shows the endgame: permanent mega-powers,
  dead mobility. **Mitigations seen:** vassal-limit penalties (CK3: each vassal over the
  limit cuts *all* vassals' tax/levy by −5%, up to −95% — a hard cap on how many you can
  milk); LD rising with subject count/strength (EU4) so an over-large domain becomes
  self-destabilizing; diminishing tribute returns.
- **Farming the defeated ("bashing"/"zeroing").** The single biggest human-retention
  killer. Mitigations: **protection windows** (Travian protection, Grepolis/EVE
  beginner + bash protection), **loyalty/regeneration timers** so you can't re-flip
  instantly (Travian/Tribal Wars +1/hr, 25 reset), garrison-or-lose (Civ VI), and making
  farming a *net-negative* for the lord (a vassal is worth more producing tribute alive
  than smashed — align the lord's incentive with the vassal's survival).
- **Coercion has to cost something** or it's spammed. Civ V tribute burns influence; CK3
  squeezing generates tyranny/legitimacy loss. Every extractive click should erode the
  relationship or a resource.
- **Instant, undefendable conquest** demoralizes (Tribal Wars noble train hitting in one
  tick). Multi-step, telegraphed sieges give the defender a window to rally allies.
- **No-loyalty subjects (EVE)** are efficient but brittle: they defect the instant a
  bigger fish appears. In a 5-10 human world, expect vassals to shop for a better lord —
  a rival can *poach* your vassal (Warhammer confederation).
- **Powerful-vassal blind spot:** the strongest subject is the most dangerous. CK3 forces
  you to *co-govern* with powerful vassals (council seats) rather than ignore them.

---

## 4. The retention problem — does "keep playing after defeat" actually retain?

The evidence is **mixed and mostly cautionary**, which is exactly why this is a hard,
valuable design:

- **Elimination is a known retention disaster** in persistent games. Grepolis devs state
  losing your only city produces a "huge" quit rate with low restart. So *not* eliminating
  is directionally correct — the pattern to beat is real.
- **But "still in the world" is not enough** if it means "still in the world as a farm."
  Travian/Grepolis/Ogame keep the loser playing and they still quit, because continued
  play = continued victimization. **Retention requires the subordinate to have a viable,
  improving trajectory**, not just a pulse.
- **EVE renting** shows humans *will* accept subordination long-term **if it's net
  positive for them** (they out-earn highsec) — the leash holds while the deal is good and
  snaps when it isn't. Voluntary, profitable vassalage retains; imposed, extractive
  vassalage churns.
- **Rubber-banding / comeback design** (game-dev consensus): the "runaway leader" problem
  kills engagement for *everyone* — the leader gets bored, the losers get bitter. Catch-up
  mechanics keep the outcome uncertain. A vassal system is a natural rubber band **if**
  the vassal's discontent/rebellion tools scale up as they're oppressed. The design goal:
  a freshly conquered vassal should feel "I have a comeback path (rebel, grow, ally),"
  not "I have a sentence."
- Practical retention levers implied: give the vassal **immediate agency the turn they're
  conquered** (deny tribute, join/found a rebellion, petition), **protection from being
  re-farmed**, **visible progress toward freedom**, and **social ties** (rebellion is
  collective — being a vassal plugs you into a faction of other vassals, i.e., a
  ready-made friend group and cause).

---

## 5. Directly-applicable ideas for Broken Oaths (steal / remix)

Opinionated, ranked by how much drama-per-complexity they buy:

1. **Rebellion gated on collective strength, not individual anger (steal CK3's 80% rule).**
   Track a "rebellion pressure" meter = combined military/economic weight of vassals who've
   joined a rebellion faction vs. the lord's own weight. It only *builds* past a threshold
   and *fires* an ultimatum/independence war at 100%. Makes rebellion a coordination game
   among humans — the whole point of the feature. *Rationale: one vassal is noise, a
   coalition is a threat; this is the core loop.*

2. **A tribute dial with an opinion/legitimacy cost (steal CK3 contract).** Let the lord
   set tribute Low/Normal/High/Massive; higher tribute pays more but *raises the vassal's
   liberty desire and generates "tyranny"* that fuels rebellion. *Rationale: makes greed a
   real, risky choice instead of a free tax.*

3. **Liberty-desire as the vassal's core stat (steal EU4).** A single 0-100 number the
   vassal and lord both watch, driven by tribute rate, how long they've been vassalized,
   relative army strength (vassals collectively outweighing the lord raises it), and
   proximity to free/rebel territory. Independence war unlocks past a threshold; the lord
   can only "annex/absorb" for good below a low threshold. *Rationale: one legible dial
   that turns the whole relationship into a tug-of-war.*

4. **Multiple subjugation flavors, not one debuff (steal EU4 subject types).** e.g.
   **Tributary** (pays resources, keeps autonomy, low LD, can even be refused) vs. **March/
   Sworn Sword** (pays no tribute but must send levies to the lord's wars, gets defensive
   bonuses) vs. **Thrall** (heavy extraction, high LD). Let the lord *choose the leash* per
   vassal. *Rationale: variety of experience prevents "vassal = punishment screen."*

5. **Loyalty-pressure geography (steal Civ VI).** Vassal cities near the lord's cities are
   "pinned" (LD suppressed); vassal cities near free players or other rebels drift toward
   independence. *Rationale: makes map position matter, gives rebels a strategy — cluster
   to build pressure — and gives lords a reason to encircle vassals.*

6. **Deny-tribute as the vassal's first act of defiance (steal Travian).** The turn you're
   vassalized you can *refuse* to pay — which stops the lord's income but flags you for
   punishment and drops your protection. A low-stakes agency lever available immediately.
   *Rationale: agency on turn one is what separates "vassal" from "eliminated."*

7. **Protection / anti-farm window on the freshly conquered (steal Grepolis/Travian).**
   A newly created vassal can't have their remaining city re-besieged for N ticks, and/or
   the lord loses tribute if the vassal is smashed to zero. *Rationale: directly attacks
   the #1 documented quit driver — being farmed after defeat.*

8. **Make the vassal worth more alive than dead (align incentives).** The lord's tribute
   income should meaningfully exceed what he'd get from razing/looting the vassal, so the
   rational lord *nurtures* his vassals. *Rationale: turns the lord from predator into
   patron; retention becomes the lord's own interest.*

9. **Powerful-vassal co-governance / vassal council (steal CK3).** The strongest vassal
   gets a seat, a title, or a cut — appeasement that also flags him as the most dangerous.
   Ignoring your biggest vassal should hurt. *Rationale: creates named rivals and
   negotiation drama instead of a faceless subject pool.*

10. **A no-annex guarantee as a negotiable submission term (steal Total War).** When
    someone's last city falls, offer branching terms: submit as tributary with a promise of
    autonomy, or fight on and risk harsher terms. *Rationale: gives the loser a decision at
    the moment of defeat — dignity and buy-in instead of a forced status.*

11. **Vassal poaching / competing lords (steal Warhammer confederation + EVE mobility).**
    A rival lord (or a rebel bloc) can bid to "liberate"/absorb another lord's vassal.
    Vassals become contested assets, not permanent property. *Rationale: keeps the vassal
    relevant to the whole server and gives the vassal leverage — shop for a better deal.*

12. **Visible comeback ladder (rubber-band the vassal).** Show the vassal an explicit path:
    grow economy → recruit fellow vassals into a faction → cross the rebellion threshold →
    independence war → freedom (and maybe a "vengeance" CB on the ex-lord). Optionally, a
    small underdog buff (reduced tribute or defense bonus) the longer they stay oppressed.
    *Rationale: the defeated player must always see "I can climb out," or they log off — the
    single biggest retention lever.*

**Two synthesis rules of thumb for the whole feature:**
- **Coordination, not RNG:** every step from "conquered" to "free" should be something
  humans *do together*, because the multiplayer social loop is the retention engine.
- **The lord's greed must be self-limiting:** vassal caps, rising LD with domain size,
  tyranny costs, and "alive > dead" tribute economics all exist to stop the snowball that
  killed mobility in EVE and drove quits in Travian/Grepolis.

---

## Sources

- CK3 Vassals / Subjects wiki: https://ck3.paradoxwikis.com/Vassals
- ACOUP, "Teaching Paradox, CK3 Part IIa: Rascally Vassals": https://acoup.blog/2022/09/23/collections-teaching-paradox-crusader-kings-iii-part-iia-rascally-vassals/
- CK3 factions guides: https://www.gamewatcher.com/news/crusader-kings-3-faction ; https://gamerant.com/crusader-kings-3-how-to-handle-factions-guide/
- CK2 Factions wiki: https://ck2.paradoxwikis.com/Factions
- EU4 Subject nation wiki: https://eu4.paradoxwikis.com/Subject_nation ; Vassal: https://eu4.paradoxwikis.com/Vassal ; Client state: https://eu4.paradoxwikis.com/Client_state
- Total War vassal wikis: https://totalwar.fandom.com/wiki/Vassal_(Total_War:_Three_Kingdoms) ; https://totalwar.fandom.com/wiki/Vassal ; PC Gamer on 3K diplomacy: https://www.pcgamer.com/total-war-three-kingdoms-finally-gets-diplomacy-right/
- Civ VI Loyalty wiki: https://civilization.fandom.com/wiki/Loyalty_(Civ6) ; CivFanatics loyalty guide: https://forums.civfanatics.com/resources/civ-vi-loyalty-guide.27114/
- Civ V annex/puppet/raze: https://www.carlsguides.com/strategy/civilization5/war/annex-puppet-raze.php ; city-state tribute: https://forums.civfanatics.com/threads/guide-to-city-state-tribute.628741/
- Travian Kingdoms tributes/protection: https://support.kingdoms.com/en/support/solutions/articles/7000083383-tributes ; https://support.kingdoms.com/en/support/solutions/articles/7000095338-denying-tributes-protection-and-hate ; conquering: https://unofficialtravian.com/2025/10/conquering-villages/
- Tribal Wars loyalty/nobling: https://tribalwars.fandom.com/wiki/Loyalty ; https://tribalwars.fandom.com/wiki/Nobling_guide
- Grepolis new-player loss / bashing: https://devblog.grepolis.com/2017/03/22/early-colonizations-the-fight-for-survival-of-new-players/ ; https://us.forum.grepolis.com/index.php?threads/quitting-the-game-why.10819/
- EVE renting analysis (INN/Imperium News): https://imperium.news/renting-in-eve-an-analysis/
- Travian conquest/retention discussion: https://forums.mmorpg.com/discussion/257091/just-because-you-dont-know-how-to-play
- Rubber-banding / comeback mechanics: https://www.gamedeveloper.com/design/the-value-of-rubber-banding-an-engagement-driver- ; https://machinations.io/glossary/comeback-mechanic
