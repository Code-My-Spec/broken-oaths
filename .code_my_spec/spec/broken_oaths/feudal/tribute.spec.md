# BrokenOaths.Feudal.Tribute

Per-turn tribute and levy resolution inside the turn pipeline, scaling to many vassal relationships per world. Gold tribute = vassal gross city-yield gold (pre-upkeep) × the lord's set rate, transferred vassal→lord with a GoldLog entry; insufficient gold accrues debt (negative balance allowed, blocks the vassal's own spending, no auto-penalty). Call-to-arms levies: the lord issues a call, the vassal answers by pledging a share of its army for the war's duration (keeping command) or refuses — refusal spikes Oath Strain and dings the Honor ledger. Story 908.

## Type

module
