# BrokenOaths.Game.Presence

Per-player online/offline status within a world — which players currently hold a live LiveView connection to the WorldServer. Fills the offline-detection gap that both Gold Bank accrual (909) and Feudal Stewardship eligibility (910) depend on: the existing world-process architecture only tracks coarse world-level presence (world pauses when presence drops to zero), not per-player status the turn pipeline / stewardship can query. Server-owned, updated on LiveView connect/disconnect, queryable as online?(world, player).

## Type

module

## Dependencies

- BrokenOaths.Game.WorldServer
