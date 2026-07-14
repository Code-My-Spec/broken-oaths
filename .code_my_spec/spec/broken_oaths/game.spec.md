# BrokenOaths.Game

The live game running on a world: player membership and spawning, units, queued orders, the 60-second turn pipeline, and per-player exploration/visibility. One WorldServer process per world serializes all mutation and broadcasts coalesced diffs over PubSub; persistence is the mutable delta over the world seed.

## Type

context

## Dependencies

- BrokenOaths.Users
- BrokenOaths.Worlds
