# BrokenOathsWeb.GameLive

The play surface — joining a world and playing on the hex globe board. Holds only a projection of WorldServer state: subscribes to the world's PubSub topic, sends commands, re-windows the fog-filtered board on diffs. Reuses the existing canvas globe renderer; every gameplay fact stays assertable through LiveViewTest.

## Type

live_context

## Dependencies

- BrokenOaths.Worlds
- BrokenOaths.Game
