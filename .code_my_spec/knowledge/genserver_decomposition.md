# Separating domain logic from concurrency (pragdave pattern)

North star for the tech-debt pass on the Game context and the game LiveViews.
The problem: `world_server.ex` (5,656 lines) couples domain logic with
concurrency — 87 `handle_call` clauses intermixed with 312 private domain
functions. Dave Thomas ("pragdave") calls this out directly: the canonical
GenServer "buries the important part — the actual implementation — in amongst
all kinds of GenServer housekeeping." (Splitting APIs, Servers, and
Implementations in Elixir, pragdave.me, 2017.)

## The three layers

1. **API** — the public interface (`BrokenOaths.Game` + domain sub-APIs). Each
   function is a thin `GenServer.call/cast` (or a direct pure-Impl call when no
   process state is needed). No logic.
2. **Server** — the GenServer (`BrokenOaths.Game.WorldServer`). `init` +
   `handle_call/cast/info` ONLY: extract the message payload, call an Impl
   function, wrap the result in the GenServer tuple. The callback body is
   mechanical:
   ```elixir
   def handle_call({:declare_independence, user, lord}, _from, state) do
     {reply, state} = Rebellion.War.declare(state, user, lord)
     {:reply, reply, state}
   end
   ```
   The ONLY things that legitimately live in the Server: state ownership,
   message dispatch, tick scheduling, and broadcasts (the genuinely concurrent
   concerns).
3. **Impl = the domain models themselves — NOT a generic `Game.Impl`/`Game.World`
   god-module.** This is the key rule. Each callback delegates to the pure
   DOMAIN MODEL that owns the concept — `Rebellion.declare/3`, `Tribute.collect/2`,
   `City.found/3`, `ProtectionPact.raise/3`, `Siege.*`, `Unit.*` — never to a
   single catch-all logic bucket (that would just be the monolith renamed). Each
   domain model is pure and process-unaware: takes `state` (or the relevant
   substructure) + args, returns `{result, new_state}` or `new_state`,
   unit-testable with no GenServer running. We already do this for leaf modules
   (Siege, Tribute, OathStrain, Rebellion.Resolution, Yields, Production,
   Research); the pass moves the 312 trapped `defp`s HOME to the model each one
   belongs to.

**Central rule:** if a `handle_*` callback contains a `cond`, a multi-step
`with`, arithmetic, or any decision, that logic belongs in a domain model — the
one that owns the concept. The callback delegates; it never decides.

**Cross-cutting operations** (e.g. `declare_independence` touches Rebellion +
Vassalage + Units + Cities + war state) are orchestrated by their OWNING domain
model calling its siblings — `Rebellion.declare/3` coordinates the vassalage
severance, army spawn, and city de-occupation by calling `Vassalage`/`Unit`/`City`.
The orchestration lives in the domain, not in the Server callback and not in a
generic core.

## Target module map

- **Server state stays in the Server** — a plain struct/map (DATA only, no
  logic). Domain models receive it (or the relevant substructure) and return an
  updated one. There is no `Game.World`/`Game.Impl` logic core.
- **The 312 trapped `defp`s move HOME to their domain model**, each of which
  grows the state-transform logic it owns and exposes it as pure functions the
  Server calls:
  - `Rebellion` — `declare/3`, lifecycle/peace/heir-gating (it orchestrates
    Vassalage severance, army spawn via `Unit`, city de-occupation via `City`).
  - `Vassalage` / `Tribute` / `ProtectionPact` — the feudal relationship,
    tribute collection, protection-call scoring.
  - `Siege` / `Combat` — attack + capture resolution.
  - `City` / `Production` / `Research` / `Unit` — city ops, build queue, tech,
    unit movement/spawn/disband.
  - each already-pure leaf module absorbs the inline logic that belongs to it.
- `Turn` (1,318) → a pure pipeline that SEQUENCES each domain's own tick phase
  (`Tribute.tick`, `Rebellion.tick`, oath-strain drift, production, …). Turn
  wires the order; each phase's behavior lives in its domain model. The Server
  calls the pipeline once per tick and re-schedules — scheduling being its only
  concurrency job.
- `Game` API (973) → split by domain (`Game.Feudal`, `Game.Cities`,
  `Game.Combat`, …), thin `GenServer.call` wrappers.
- LiveViews (`play.ex` 4,248, `show.ex` 1,952) — same shape one layer up:
  imperative shell (mount/handle_event/render-dispatch) delegating to `Game` +
  pure view-model builders + function components. Panels already extracted
  (city/chat/alliance/unit) are the precedent.

## Target bounded contexts

Today's flat `BrokenOaths.Game.*` (30+ siblings) splits into proper contexts,
each owning its aggregates + logic. `WorldServer` is demoted to a coordination
shell in `Simulation` that routes each message/tick to the owning context.

| Context | Type | Children (aggregates / logic) |
|---|---|---|
| `Worlds` *(exists)* | context | globe, generator, projection, regions, resources, noise, world |
| `Vision` | context | visibility, exploration, fog (leans on `Worlds`) |
| `Players` | context | player, honor, presence |
| `Technology` | context | research (tech tree), player_research |
| `Cities` | context | city, production, improvement, yields |
| `Units` | context | unit, order (movement) — ALL units incl. civilian (settler/worker) |
| `Combat` | context | combat, siege, city_defense, camp(s), barbarian_ai — base/cross-cutting, depended on by Units + Cities + Feudal |
| `Feudal` | context | vassalage, vassalization, tribute, oath_strain, protection_pact, rebellion, rebellion_pact(+member), stewardship, steward_log, levy, bank, gold_log |
| `Diplomacy` | context | alliance, chat, known_player, discovery, cooperation |
| `Simulation` | coordination_context | turn, spawner, order-processing, **WorldServer** (the tick runtime) |

Dependency direction flows toward the base: `Combat`/`Vision`/`Technology` are
depended-on; `Feudal`/`Cities`/`Units` sit above; `Simulation` orchestrates
everything and depends on all. No cycles (the CodeMySpec graph enforces this).

The re-contexting rides ALONG with the pragdave pass, domain by domain: when a
domain's stolen logic moves home out of `WorldServer`, the model also moves into
its context namespace and the arch graph is updated in the same slice.

## Execution discipline (every slice)

- **Behavior-preserving.** The 1,238 tests + ~40 spex are the guardrail — they
  must stay green after every extraction, unchanged.
- **One cohesive slice per commit.** Move a domain area's `defp`s into an Impl
  module, reduce its callbacks to delegations, run `mix test` + the affected
  spex, commit. Never a big-bang rewrite.
- **Radar:** `scripts/loc.sh` tracks the offender list; the top of it should
  shrink each pass.

## Sources
- [Splitting APIs, Servers, and Implementations in Elixir — pragdave](https://pragdave.me/thoughts/active/2017-07-13-decoupling-interface-and-implementation-in-elixir.html)
- [Elixir for Programmers — should we adopt Dave Thomas' way of organizing GenServers? (ElixirForum)](https://elixirforum.com/t/elixir-for-programmers-course-should-we-adopt-dave-thomas-way-of-organizing-genservers/14192)
- [pragdave/component (GitHub)](https://github.com/pragdave/component)
