# Gem-Weary Wes

Proto-persona (PM self-identification + secondary research), researched
2026-07-13. Decision stake: Broken Oaths' core loop — browser-first,
session-friendly, collaborative-but-casual, no pay-to-skip monetization.

## Role

Casual turn-based strategy / city-builder player in his mid-30s to 50s.
Plays free browser games — Forge of Empires, Elvenar, Travian-likes,
SimCity BuildIt-style builders — the "buy gems to finish upgrading your
farm" genre. He is squarely mainstream, not niche: casual games attract
~63% of gamers globally (~1.95B players), the average gamer is now 36,
and browser games are a ~$7.8B market [E1, E2, E3]. He knows the genre's
tricks and plays anyway, because nothing else fills the same slot.

## Goals

- **Persistent, patient progress.** He wants a city/empire that grows
  over months, not a match that resets. Veterans describe the appeal as
  "a slow rich and complex long-term strategy game for patient players"
  and report playing years without spending [E4].
- **Collaborate with friends, lightly.** Guilds/alliances are "the
  social backbone" of these games — trades, advice, shared projects
  [E5]. He wants teamwork and a reason to check what friends did, at
  turn-taken-at-leisure pace, not scheduled raid nights [E6].
- **Hop in from any browser, instantly.** No install, no launcher, no
  2GB download for a 15-minute break. Click a link, play, close the tab
  without a trace [E7].

## Pain Points

- **Gem/timer paywalls.** Progression gated by wait timers that premium
  currency skips: "it takes 4-14 days that would take 4 minutes if you
  are willing to spend $1 to $7"; one reviewer spent "$2,000" and got
  "only about 60% through the game" [E8]. Energy/timer systems are
  designed to convert frustration into purchases [E9].
- **The game becomes a job.** Daily-login mechanics, event FOMO, and
  decay "basically force you to log in and play every day" [E10]. He
  wants to *want* to come back, not to owe the game attendance.
- **Alliance obligation creep.** Strict guilds impose participation
  quotas; casual players ask for "clear & fair rules... I don't expect
  to have to give everything I have" and leave when the social layer
  turns into a second boss [E11].
- **Rug-pulls on invested time.** Rule changes and event manipulation
  after players have sunk months in: "Foe tricks you into investing
  time, then switches rules" [E12]. Trust, once lost, ends the game.

## Context

Plays in short sessions — a browser tab at work, the couch in the
evening. Work-break browser play favors 2–10 minute rounds you can
quit mid-turn without guilt, muted by default, invisible to IT because
nothing installs [E7, E13]. Median mobile-style casual sessions run
~5 minutes; older players (40s–50s+) put in the most total daily time
across such sessions [E2]. His friends are in different time zones and
schedules, which is why asynchronous turn-taking — "turns can be taken
at leisure with no rush" — is the only multiplayer that survives
contact with adult life [E6].

## Decision Drivers

- **Zero-friction entry**: a URL is the whole install; works on the
  phone browser too [E7].
- **Fair progression**: patience must be a complete substitute for
  payment. Free-path players who stay years are the proof the genre
  works without gems [E4]; pay-to-skip is why they quit [E8, E9].
- **Safety of invested time**: he stays where "you can't lose
  everything you sunk your time into" — no offline raiding losses, no
  resets, no rule changes that orphan his city [E4, E12].
- **Social without obligation**: alliance features must reward showing
  up without punishing absence [E5, E11].

## Quotes

- "It takes 4-14 days [for something] that would take 4 minutes if you
  are willing to spend $1 to $7." — Metacritic reviewer jdefdolnet [E8]
- "[FoE is] a slow rich and complex long-term strategy game for patient
  players." — Metacritic reviewer Zob-555 [E4]
- "[The game] basically forces you to log in and play every day." —
  Metacritic reviewer 123oleary [E10]
- "I want a guild with clear & fair rules... I don't mind contributing
  to a guild but... I don't expect to have to give everything I have so
  that I can't progress." — Forge of Empires forum player [E11]
- "You can't lose everything you sunk your time into." — Metacritic
  reviewer Tick, on why optional PvP keeps him playing [E4]

## Anti-Patterns

Design traps that break this persona (each maps to a pain point):

- Wait timers with a paid skip — the defining sin of the genre [E8, E9].
- Daily-login streaks, decay, or events that punish a week away [E10].
- Alliance mechanics with participation quotas or kick-on-inactivity
  pressure [E11].
- Requiring an install, an account wall before play, or a client
  download [E7].

## Evidence

- E1: Casual genre reach (63% of gamers, ~1.95B) — SQ Magazine gamer
  statistics; corroborated by Statista casual-gaming topic and GAM3S.GG
  demographics report.
- E2: Age/session patterns (average gamer 36; 40s–50s+ highest daily
  minutes; ~5 min median sessions) — SQ Magazine; Udonis 2026 gamers
  report; inStreamly demographics.
- E3: Browser games market ~$7.81B (2025) — The Business Research
  Company browser games report.
- E4: Patient long-term play without spending — Metacritic user reviews
  (Kylvexus, Zob-555, Tick); AlternativeTo user commentary.
- E5: Guilds as social backbone, free trades, advice — FoE Guides "The
  Function of a Guild"; FoE Fandom wiki Guild page; FoE forum guild
  thread.
- E6: Async turn-taking fits friends' schedules — TapSmart async
  multiplayer roundup; Slant async Android games; Quarter To Three
  async co-op thread.
- E7: No-install instant play, quit-without-guilt sessions — GameSpace
  instant-play feature; DANY Games browser-vs-downloads; TechPatio;
  Arcade Beasts work-games guide.
- E8: Pay-to-skip cost quotes — Metacritic user reviews (jdefdolnet,
  Genghis90272, apaeth); Reviewopedia FoE reviews; AppGrooves negative
  review highlights.
- E9: Timer/energy systems engineered to monetize frustration — Adrian
  Crook energy-systems analysis; How-To Geek worst monetization
  practices; Reviewopedia.
- E10: Daily-login obligation — Metacritic (123oleary); Adrian Crook
  (return-visit design); Reviewopedia.
- E11: Casual guild expectations, obligation creep — FoE forum "what
  does a new player need in a guild"; FoE Guides (strict-requirement
  guilds); Reviewopedia (dominant guilds locking out casual ones).
- E12: Rule-change betrayal of invested time — Metacritic (BriefNotes);
  Reviewopedia (event manipulation, live-server account alterations);
  Trustpilot InnoGames reviews (via search excerpts; direct fetch
  blocked).
- E13: Work-break session shape (2–10 min, mute-friendly, no IT
  footprint) — Chihuahua Games idle-at-work guide; Uselessweb work
  games guide; Medium 47-browser-games roundup.
