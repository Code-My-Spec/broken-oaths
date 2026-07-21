# Convention: units, tech unlocks, and how to keep research coupled to its effect

Written after finding Sailing shipped as a **dead tech**: it was researchable,
counted toward the age, and its `unlock:` string read "Enables Galleys and
coastal exploration" — but no Galley unit existed, was buildable, or could move.
The tech promised a unit nobody owned.

## Why it happened

The tech tree was built as **one story** with each tech's effect described as a
forward-looking `unlock:` string. Techs whose effect something else owned got
wired (Pottery→Granary, Mining, Bronze Working). Sailing's effect was a **unit
that was never a tracked requirement** — just prose in a comment ("ships in
later stories"). Nothing could ever fail because of the Galley's absence, so it
silently never got built.

By contrast, `:archer` and `:bronze_spearman` are complete — because each was
its **own story that owned its tech gate** (`opts[:archery?]`,
`opts[:bronze_age?]`). That is the pattern that works.

## The convention

**1. The unit is the story; the tech gate is one of its acceptance criteria.**
Do NOT track a buildable thing (unit, improvement, building, wonder) as a
line-item under the tech tree. Give it its own story, and make "requires tech X"
a rule-bearing scenario ON THAT STORY, e.g.:

> Given a coastal city and Sailing completed, the Galley appears in the build
> menu; without Sailing it does not; a built Galley moves on water.

That scenario cannot pass until BOTH the gate and the working thing exist, so the
story cannot be marked done half-built. **One story per buildable unit, and the
tech gate lives as a criterion on the unit's story — never as an `unlock:` string
on the tech.**

**2. Guardrail — a tech may not advertise an effect it does not deliver.** A
tech's `unlock` field (and any player-facing description of it) must correspond
to a delivered capability, OR be explicitly marked deferred and linked to the
story that will deliver it. This turns a silent broken promise ("Enables
Galleys") into a visible, tracked dependency. A "structure-only" tech (researches
but does nothing) is never shipped without that link.

## Where each lives

- **Unit story + tech-gate criterion** → CodeMySpec stories (Three Amigos). This
  is the primary mechanism; it is what makes "everything gets done."
- **The guardrail** → a design rule on the `BrokenOaths.Technology.Research`
  component (its spec), plus this doc.
- **Honesty of the `unlock:` string** → keep it accurate in
  `lib/broken_oaths/technology/research.ex`; a not-yet-delivered unlock reads
  "(deferred — story NNN)", not as if it were done.

## Applies to

Every future buildable/unlockable: additional units (cavalry, siege, ships),
improvements, buildings, wonders, and age-gated abilities. Galley (story 921) is
the exemplar built to this convention.
