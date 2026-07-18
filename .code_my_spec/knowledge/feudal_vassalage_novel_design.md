# Broken Oaths — The Vassalage Drama Layer (Novel Design)

Design research + ideation for the cornerstone feature: capturing a player's LAST city
does not eliminate them. They become your **vassal** — a real human who keeps playing,
pays tribute, and can plot to break free. This document designs the emergent-drama layer
that turns "vassalage" from a loser's debuff into the thing people tell stories about.

> Core thesis: **The debuff is not the feature. The negotiation is.** A vassal is not a
> defeated player; they are a co-author of a political drama who happens to be starting
> from behind. Every mechanic below is judged by one question: *does it make staying and
> scheming more interesting than rage-quitting?*

---

## 0. Reference distillation — what actually generates drama

Before the design, the load-bearing lessons pulled from the reference systems. Each one
maps to a mechanic later.

- **Neptune's Pride** — the drama is that *nothing is enforced by the engine*. Alliances,
  tribute, non-aggression are all just promises between humans, and the whole game is the
  timing of when you break one. Real-time-with-delay (fleets/orders take real hours) means
  betrayal is a *plan you commit to before anyone can react*. The slow clock is what makes
  it feel intelligent instead of twitchy. → **Rebellions must be pre-committed and travel
  through real time, so the drama is in the plotting window, not the dice.**
- **Shadow of War Nemesis** — emotional weight comes from *remembered specifics*. The orc
  that betrays you quotes the battle where you spared it. Loss of a unit feels like losing
  a person because the system logged your shared history. → **The lord/vassal bond must
  accumulate a remembered, referenceable history — grudges and debts with receipts.**
- **EVE Online heists** (Judge, Guiding Hand, Band of Brothers) — the biggest stories are
  *inside jobs*: someone trusted for months who held real assets and walked. The stakes
  were real because trust was mechanically load-bearing (they held the keys). → **Give
  vassals real, load-bearing responsibilities inside the lord's realm so betrayal costs
  the lord something concrete, not just a border skirmish.**
- **EU4 Liberty Desire** — a single 0–100 pressure number that rises with the vassal's
  relative strength and falls with the lord's investment/relations/reputation. Clean, but
  *AI-tuned and gameable* (fort-loading a vassal into debt). → **Steal the pressure-gauge
  shape, but drive it with human-legible, hard-to-cheese inputs and make it visible to
  both sides as a social signal.**
- **CK3 feudal contract** — vassalage is a *negotiable contract* (tax %, levy %, plus
  grantable rights: fortification, coinage, council seat). Raising demands costs opinion
  and tyranny; granting rights buys loyalty. Factions (independence / liberty /
  dissolution) are the organized-rebellion layer. → **Make the oath an editable contract,
  and make raising vs. granting terms a real, costed negotiation.**
- **Diplomacy / Werewolf** — coordinated betrayal is fun when it's *simultaneous and
  hidden until reveal*. The delicious part is the table not knowing who's really in.
  → **Rebellions should have a hidden-commit / simultaneous-reveal beat.**

---

## 1. The retention / anti-quit design — giving a defeated human agency

The failure mode: conquest feels terminal, the player closes the tab. Every mechanic here
exists to replace "I lost" with "I'm playing a different, spicier game now."

### 1.1 The moment of capture is an *offer*, not a death screen
When your last city falls, you do not see "You have been eliminated." You see a **Terms of
Oath** screen: the conqueror's default contract (tribute rate, obligations) and three
things you *keep*. Framing it as an oath you *swear* (with a click that literally reads
"I swear fealty… for now") gives the player an act of agency at the lowest moment.
*Inspired by: CK3 contract + the "for now" is pure Neptune's Pride betrayal-intent.*

**What a vassal keeps (the agency floor):**
- **Their city, their production, their units.** They are not spectating. They run a real
  (smaller) economy. The lord takes a *cut*, not the keys.
- **A Hidden Agenda.** At capture the vassal privately picks a win condition of their own:
  *Restore* (regain independence), *Usurp* (become the lord by inheriting/killing up),
  *Kingmaker* (be the vassal who decides which lord wins the world), or *Merchant Prince*
  (get rich under protection, never rebel). This reframes the whole rest of the game as
  *their* story, not a sentence. → **This is the single most important anti-quit lever.**
- **A grievance ledger** that starts filling immediately (see 1.3).

### 1.2 The underdog has *asymmetric* toys the top dog doesn't
Being small should unlock a different, sharper toolkit — being a vassal is a *class*, not
just a smaller version of being a lord. Vassals can:
- **Sedition / whisper network:** send tribute-funded covert messages to *other* vassals of
  the same lord that the lord cannot read (but can detect volume/heat of — see 3.4).
- **Skim:** secretly under-report tribute, banking a hidden war-chest for a future revolt,
  at the risk of audit and punishment. *Directly the EVE inside-job fantasy, miniaturized.*
- **False loyalty bonus:** a vassal who has *never* missed tribute and *never* whispered
  accrues a hidden "Trusted" status that grants a one-time devastating rebellion bonus.
  Loyalty is a weapon you're saving. *Nemesis "the one you trusted" + Diplomacy.*
- **Sabotage as the weak's artillery:** can't win a field battle, but can poison a well,
  spike a garrison, or leak the lord's fleet movements to the lord's rivals.

### 1.3 Remembered grudges & debts (the Nemesis import)
Every interaction between a specific lord and vassal writes to a **shared, referenceable
ledger** that both can see: "Turn 214: Lord razed your second city." "Turn 260: You paid
tribute 14 turns running." "Turn 300: Lord left your border undefended during the barbarian
wave." These entries are not flavor — they are *inputs* to loyalty (section 2) and
*modifiers* to rebellion odds (section 3), and they surface as quotable lines ("You let my
city burn") in rebellion declarations and chat. The point: the relationship has *memory*,
so betrayal and forgiveness both mean something.

### 1.4 Comeback ramps so hope is mathematically real
Rage-quit happens when the gap looks unclosable. Provide visible ladders:
- **Vassal tech/units the lord can't build** (guerrilla, assassin, agitator) — asymmetry
  makes small players *interesting* to play, not just weak.
- **Tribute rebates on milestones** ("survived 50 turns as a vassal → -20% tribute").
- **The enemy-of-my-enemy market:** rival lords will *fund* your rebellion (see 2.4).
  Being someone's vassal makes you a valuable asset to their enemies — you have leverage
  the moment you're conquered.

### 1.5 Never a dead account: the "ghost still bites" rule
If a vassal *does* go inactive/quit, they don't become a free tribute farm. Their city
decays into a **restless holding**: tribute drops, unrest rises, and it can spontaneously
throw a (weak, AI-run) peasant revolt — so the lord can't just farm abandoned vassals, and
a returning player finds a city that's been *waiting to explode* in their favor. This keeps
the map alive and makes quitting less rewarding for the lord to have caused.

---

## 2. The reciprocal vassalage model — a two-way oath

Purely extractive tribute is a debuff and will be hated. The design makes vassalage a
**bilateral contract with obligations flowing both directions**, and a loyalty pressure
gauge that punishes lords who take without giving. This is where "Broken Oaths" earns its
name: an oath has *two* signatories, and either can break it.

### 2.1 The Oath Contract (editable, costed, mutual)
Modeled on CK3's feudal contract but two-sided. The oath has **Vassal Obligations** and
**Lord Obligations**, each a set of toggles/sliders with a loyalty price.

**Vassal owes (levers the lord wants up):**
- **Tribute** — % of gold/production skimmed to the lord.
- **Levy** — % of the vassal's military the lord can call to *his* wars.
- **Vision / March rights** — lord sees through the vassal's territory; can move armies through it.
- **Deference** — vassal cannot declare war on third parties without the lord's leave.

**Lord owes (levers the vassal wants up — the new, novel half):**
- **Protection Pact** — a binding promise: if the vassal is attacked by a third party, the
  lord *must* respond within N turns or eat a massive loyalty/honor penalty across ALL his
  vassals (public oath-breaking). This is the keystone reciprocal mechanic — it makes the
  lord's tribute feel *earned* and makes neglect visibly costly.
- **Spoils Share** — the vassal gets a cut of loot/land from wars they were levied into.
  Extraction becomes partnership.
- **Autonomy Grant** — lord waives Deference/March; vassal runs freer. Cheap loyalty, but
  the lord loses control.
- **Shared Vision** — lord shares his map/intel with the vassal (huge to a small player who
  is blind).
- **Wardship / Investment** — lord can *gift* tech, gold, or a unit to a vassal (raising
  them up). Counterintuitively strengthens a potential rebel — the trust dilemma is the game.

**Contract change is a negotiation, not a fiat.** Raising vassal obligations or lowering
lord obligations is **oath-straining**: it spikes loyalty pressure and writes a grudge.
Granting rights is **oath-honoring**: cheap, durable loyalty. Asymmetry (à la CK3: demands
cost far more than concessions) means good lords rule by generosity, bad lords by fear —
and both are viable, *different* playstyles.

### 2.2 Loyalty as a visible, human-legible pressure gauge
One number per bond, **0–100 "Oath Strain"** (rebranded liberty desire), shown to *both*
players. Transparency is deliberate: it's a social signal, like a relationship status, that
invites conversation ("your strain's at 70, talk to me").

**Strain RISES from (neglect / extraction):**
- High tribute/levy relative to lord obligations (the imbalance, not the absolute).
- **Unhonored protection** — lord failed a Protection Pact call (big spike + grudge).
- Vassal's relative strength growing (they can imagine winning). *EU4's core input.*
- Lord ignoring the vassal (no messages, no gifts, no shared spoils over long stretches).
- Neighboring vassals rebelling (contagion — see 3.3).
- Grudge-ledger entries (razed cities, betrayals, broken promises).

**Strain FALLS from (investment / relationship):**
- Honored protection calls (lord showed up → durable trust).
- Spoils shared, autonomy/vision granted, gifts given.
- Time served without incident (habit/inertia — the CK3 "content vassal" drift).
- **Mutual grudge against a common enemy** (nothing bonds like a shared foe).

**Design tuning for real-time human play (the critical difference from EU4):**
- **Strain is sticky and slow.** In a 60s-turn persistent world you cannot have a gauge
  that swings in minutes — it must move on the scale of hours/days so that the *social*
  layer (chat, negotiation) has time to operate. The gauge is a slow tide; the human
  drama is the weather on top of it.
- **Strain gates *possibility*, not automatic action.** Unlike EU4 where high liberty
  desire auto-fires an AI rebellion, here strain only sets the *odds and the ceiling* of a
  rebellion that a **human must choose to declare**. High strain = "the powder is dry."
  The spark is always a person. This is what keeps agency human and prevents the gauge from
  playing the game for you.

### 2.3 Honor / reputation — the lord's public credit score
A lord has a world-visible **Honor** rating built from kept vs. broken oaths (protection
calls honored, promises kept, vassals treated well vs. razed). Honor is *strategically
material*, not cosmetic:
- **High Honor:** future conquered players *swear in at lower strain* (they expect fair
  treatment) and are less likely to rebel. Vassals recruit-pitch their friends to your
  realm. You can rule wide and stable.
- **Low Honor / Oathbreaker:** everyone you conquer starts hot, rival lords get diplomatic
  bonuses against you, and your vassals coordinate more easily. Tyranny is powerful but
  *brittle* — it must win fast.

This makes the reciprocal layer matter even to a purely ruthless optimizer: reputation is a
resource you spend.

### 2.4 The rival-lord market (vassals as contested assets)
A vassal is leverage for the lord's *enemies*. Rival lords can covertly **court** another
lord's vassal: offer to fund a rebellion, promise better oath terms post-flip, or buy
intel. This turns every vassal into a contested asset and gives the vassal a *negotiating
table* — they can play lords against each other, auction their loyalty, or run a double
agent. *EVE espionage + Diplomacy, systematized.*

---

## 3. Rebellion as a set-piece — the climactic Broken Oath

A rebellion must feel like a *heist movie's third act*, not a die roll. The design front-
loads all the drama into a **plotting window** and a **simultaneous reveal**, then resolves
with math the players understood going in.

### 3.1 The three shapes of revolt
1. **Lone Uprising** — one vassal declares. Fast, desperate, usually needs a distraction
   (lord at war elsewhere). The underdog's Hail Mary.
2. **Sworn Conspiracy** — multiple vassals secretly commit to a *synchronized* revolt (see
   3.2). The premium, high-drama path. Coordinated via chat.
3. **The Cascade (lord-death / decapitation)** — if a lord is killed or their capital falls,
   **every** vassal is instantly released to a rebellion opportunity at max strain, all at
   once. The empire can dissolve in a single dramatic night. This is the "kill the king"
   fantasy and the reason lords must keep vassals *happy* rather than just strong — a wide
   tyranny is one bad battle from total collapse.

### 3.2 The plotting window (hidden commit → timed reveal)
The Neptune's-Pride-style pre-commit beat, which is where the game's best stories will live:
- A conspirator opens a **Pact of Broken Oaths**: names a **strike turn** (some hours out,
  real time), and secretly invites other vassals via the whisper network.
- Each invitee **commits or declines in secret.** Committed strength is *hidden* from the
  lord (but the lord may get fuzzy signals — see 3.4). Nobody, not even the plotters, sees
  the *full* roster until reveal — you're trusting humans who could be the lord's informant.
- On the strike turn, **all commitments reveal simultaneously** and resolve together. The
  terror-and-thrill is the reveal: did the three vassals who swore in actually show, or did
  one sell you out and one chicken out, leaving you exposed?
- **Betrayal is a first-class move:** an invited vassal can secretly **inform** the lord for
  a reward (tribute forgiveness, land, a rise in station). The informer's dilemma — take the
  guaranteed payout or gamble on freedom — is the beating heart. *Werewolf + EVE inside-job.*

### 3.3 City-flip math (rewards loyalty history, not luck)
When a rebellion resolves, each contested city computes a **flip probability** the players
could see and plan around. Illustrative model:

```
FlipChance(city) =
    base(strain)                         // 0..~55%, the dry-powder from the gauge
  + committed_rebel_strength_ratio        // your muscle vs. the lord's local muscle
  + surprise_bonus                        // lord at war / distracted / capital threatened
  + grudge_bonus                          // razed cities, broken protection pacts, etc.
  + coordination_bonus                    // # of synchronized conspirators, superlinear
  + trusted_striker_bonus                 // the "never rebelled before" one-shot payoff
  - lord_response_strength                // levies the lord can rush + loyal-vassal aid
  - honor_bonus(lord)                     // fair lords are harder to flip
  - informer_penalty                      // every leak drops the whole conspiracy's odds
```

Design intents baked into the shape:
- **Loyalty/tribute history is a stat, not flavor** — the trusted-striker one-shot and the
  grudge terms mean the months of relationship *are* the dice you rolled long ago.
- **Coordination is superlinear** — three synchronized vassals should be far scarier than
  three lone revolts, to push players toward the chat-plotted set-piece.
- **The lord's loyal vassals fight for him.** A rebellion is vassals vs. vassals as much as
  vs. the lord — the realm takes sides, which is where cross-player rivalries ignite.
- **Everything is inspectable pre-commit.** Like Neptune's Pride, the numbers are visible so
  the drama is in the *human read* ("will he actually show up?"), never in a hidden RNG feel.

### 3.4 The lord's counter-play (so it's a duel, not an ambush)
A rebellion the lord can't see coming is unfair and un-fun for the lord. Give the lord
detection and pre-emption without removing vassal secrecy:
- **Heat, not content:** the lord sees *whisper volume/temperature* among his vassals (a
  rising "unrest" needle) but not the messages. He knows something's brewing, not what.
- **Loyalty audits, spies, informers:** the lord can plant a spy, buy an informer, or run an
  audit to unmask a plot — at the cost of Honor if he's wrong (paranoid tyranny corrodes
  trust). *EVE counter-espionage.*
- **Pre-emptive concessions:** facing a hot realm, the lord can *lower* terms, grant rights,
  gift, or honor an overdue protection call to cool strain before the strike turn — turning
  the plotting window into a *negotiation* the lord can still win with generosity, not just
  swords. This is the reciprocal layer paying off dramatically.

### 3.5 The aftermath writes the next story
- **Successful revolt:** vassal is free (or *becomes* the new lord if they Usurped),
  grudges reset into fresh Honor stakes, and the ex-lord's other vassals watch — strain
  contagion spikes across the realm. One successful revolt can trigger the cascade.
- **Failed revolt:** the lord chooses **mercy or ruin** — forgive (Honor up, a bought
  loyalty) or raze/strip the rebel (fear up, Honor down, a permanent grudge in the ledger).
  Every rebellion, win or lose, *deepens* the relationship rather than ending it.

---

## 4. Bold mechanic ideas, ranked by cornerstone potential

Each: one-line pitch + main risk. Ranked by "rad, talked-about, defining."

1. **The Hidden Agenda at capture** — every conquered player secretly picks their own win
   condition (Restore/Usurp/Kingmaker/Merchant Prince), so defeat reframes as a new game.
   *Risk: agendas that never resolve feel like dead flavor; each needs real payoff hooks.*
2. **Pact of Broken Oaths (hidden-commit, timed, simultaneous-reveal conspiracy)** — the
   heist-movie plotting window where vassals secretly sync a revolt and anyone can inform.
   *Risk: requires enough concurrent vassals of one lord to reach critical mass; small
   worlds may starve it.*
3. **The Protection Pact (binding lord obligation)** — the lord *must* defend a vassal or
   publicly break his oath and hemorrhage loyalty realm-wide. Makes tribute feel earned.
   *Risk: grief potential — vassals baiting attacks to force the lord into no-win calls;
   needs cooldowns/verification.*
4. **Honor as a world-visible credit score** — kept vs. broken oaths set how future conquests
   swear in; tyranny becomes powerful-but-brittle, generosity becomes stable-but-slow.
   *Risk: balancing so both honor and tyranny are viable, not one dominant.*
5. **The Trusted Striker one-shot** — never rebelling and never skimming banks a devastating
   surprise-revolt bonus; loyalty becomes a weapon you're saving. *Risk: encourages passive
   turtling until the payoff; cap the wait or decay it.*
6. **Lord-death Cascade** — killing/decapitating a lord releases ALL vassals into
   simultaneous revolt; empires can dissolve in one night. *Risk: swingy; a lucky
   decapitation erases hours of play — needs a partial/staggered release valve.*
7. **The rival-lord vassal market** — enemies covertly fund your rebellion / court your
   vassals; every vassal is a contested asset with a negotiating table. *Risk: diplomatic
   complexity spiral; hard for new players to read.*
8. **Skim & Audit** — secretly under-pay tribute to bank a war-chest, risking discovery.
   The EVE inside-job in miniature. *Risk: fiddly bookkeeping; must stay legible.*
9. **Grudge Ledger with quotable lines** — a remembered shared history that feeds loyalty
   math and surfaces as barks in revolt declarations ("You let my city burn"). *Risk:
   generation quality; canned lines get stale fast.*
10. **Whisper-heat detection** — the lord feels the *temperature* of vassal conspiracy
    without reading it, turning surveillance into a bluffing minigame. *Risk: tuning the
    signal so it's neither useless nor a plot-killer.*
11. **Asymmetric vassal-only tech (guerrilla/assassin/agitator)** — being small unlocks a
    different toolkit, so vassals play a sharp distinct game, not a weak one. *Risk: balance
    and scope creep of a whole second tech line.*
12. **The Informer's Dilemma payout** — an invited conspirator can betray the plot to the
    lord for station/land; the guaranteed-payout-vs-freedom choice. *Risk: if informing is
    too rewarding, no conspiracy ever survives.*
13. **Restless Holdings (quit-proofing)** — abandoned vassals decay into revolt-prone cities
    instead of free tribute farms. *Risk: AI-run revolts feel noisy if too frequent.*
14. **Mercy-or-Ruin aftermath** — post-revolt the lord publicly chooses forgiveness (Honor)
    or reprisal (fear), a dramatic character-defining beat. *Risk: mostly upside; ensure the
    "mercy" path is mechanically competitive, not just role-play.*
15. **The "…for now" oath ritual** — swearing fealty is an explicit, flavored player action
    that plants public betrayal-intent, setting the tone that every oath is provisional.
    *Risk: pure flavor unless tied to a real mechanic (tie it to the Trusted Striker clock).*

---

## 5. Open design questions for the product owner

Genuine forks — decide these and the game bends in different directions.

1. **Concurrency floor for the set-piece.** Sworn Conspiracies need several vassals under
   one lord at once. In a 5–10 player world with a real-time clock, does a single lord ever
   hold enough vassals to make coordinated revolt the *norm* rather than a rare event? If
   not, do we lean into **1-on-1 lord/vassal duels** as the primary drama and treat mass
   conspiracy as an endgame-only spectacle? This is the biggest structural fork.

2. **Transparency of the strain gauge.** Fully visible to both (relationship-status, invites
   negotiation) vs. hidden/fuzzy (paranoia, misreads, Neptune's-Pride bluffing)? Visible is
   more *social*; hidden is more *dramatic*. Could also split: vassal sees their own exactly,
   lord sees only a band.

3. **How binding is a binding oath?** Should Protection Pacts be *engine-enforced* (lord
   literally auto-penalized) or *socially enforced* (just tracked as Honor, humans judge)?
   Enforced = reliable drama but gameable; social = truer to "nothing is enforced" Neptune's
   ethos but can feel toothless. Where on that spectrum?

4. **Is tribute a mechanical must, or can vassalage be near-symbolic?** A light touch
   (mostly reputation + politics, tiny tribute) maximizes agency and retention; a heavy
   touch (real economic extraction) makes conquest *worth it* for the lord. Which side does
   the economy need to lean?

5. **Elimination — ever?** Is there ANY path to truly removing a player (repeated failed
   revolts → exile? selling a vassal to another lord? a vassal *choosing* to be absorbed),
   or is "no one is ever out" an inviolable pillar? Affects world-length and endgame.

6. **Win condition & vassal victory.** Can a *vassal* win the world (via Usurp/Kingmaker), or
   only lords? If vassals can win, the conquered player has a live victory path (huge for
   retention) but "losing" gets fuzzy. If only lords win, agendas are consolation prizes.

7. **Cascade swinginess.** Is a lord-death total-dissolution cascade *thrilling* or
   *rage-inducing* for the lord who spent hours building? Do we want a staggered/partial
   release, a grace period, or an all-at-once guillotine? Tune for the story you want told.

8. **Griefing guardrails.** Protection-Pact baiting, whisper-spam, informer farming, tribute-
   skim exploits — which of these do we design *out*, and which do we embrace as "politics is
   dirty"? The line between emergent drama and toxic misery is a values call, not a math one.

9. **Chat as first-class mechanic vs. side-channel.** Do we build in-game structured
   diplomacy tools (formal pact objects, secret channels, betrayal buttons) or lean on freeform
   chat + light mechanical hooks? More structure = more legible drama and better new-player
   onboarding; more freeform = more EVE-like emergent chaos.

10. **Honor legibility for optimizers.** How hard do we make it for a ruthless min-maxer to
    *ignore* the reciprocal layer? If tyranny is even slightly optimal, the beautiful two-way
    negotiation withers. The reciprocal model only sings if generosity is genuinely
    competitive — is that a balance target we're committing to?

---

## Sources
- [Neptune's Pride — Wikipedia](https://en.wikipedia.org/wiki/Neptune's_Pride) · [Analysis: The Icy Grandeur of Neptune's Pride (Game Developer)](https://www.gamedeveloper.com/game-platforms/analysis-the-icy-grandeur-of-i-neptune-s-pride-i-)
- [Shadow of War Nemesis system (RPG Site)](https://www.rpgsite.net/feature/6192-shadow-of-war-domination-guide-the-nemesis-system-betrayal-death-threats-resurrection-and-more-orc-dominating-mechanics-explained) · [How the Nemesis System Creates Stories (Medium)](https://medium.com/@niklaseckstein/how-the-nemesis-system-creates-stories-d26754b30d2e)
- [EU4 Subject nation / Liberty Desire (Paradox Wiki)](https://eu4.paradoxwikis.com/Subject_nation)
- [CK3 Feudal Contract & Vassals (GameWatcher)](https://www.gamewatcher.com/crusader-kings-3-feudal-contract-vassals) · [CK3 Subjects (Paradox Wiki)](https://ck3.paradoxwikis.com/Vassals) · [Teaching Paradox: Rascally Vassals (ACOUP)](https://acoup.blog/2022/09/23/collections-teaching-paradox-crusader-kings-iii-part-iia-rascally-vassals/)
- [Inside the biggest heist in EVE Online history (PC Gamer)](https://www.pcgamer.com/inside-the-biggest-heist-in-eve-online-history/) · [How EVE Players Pulled Off The Biggest Betrayal (Kotaku)](https://kotaku.com/how-eve-players-pulled-off-the-biggest-betrayal-in-its-1806168400)
