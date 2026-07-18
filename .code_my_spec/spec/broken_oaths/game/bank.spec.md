# BrokenOaths.Game.Bank

Gold-bank core for story 909: a per-player capped bank that captures offline earnings. While a player is online gold flows to the usable treasury; while offline, per-turn earnings accrue into the bank up to its cap, then hold (overflow wasted, never lost). Collect sweeps bank -> treasury; upgrade raises the cap for a gold/production cost, blocked when unaffordable. Runs in the turn pipeline, gated by per-player online/offline status (Game.Presence). Banked amount + cap are fields on the Player schema (spec-time), mirroring how Honor/gold already live on Player.

## Type

module

## Dependencies

- BrokenOaths.Game.Player
- BrokenOaths.Game.Presence
- BrokenOaths.Game.Turn
- BrokenOaths.Game.Yields
