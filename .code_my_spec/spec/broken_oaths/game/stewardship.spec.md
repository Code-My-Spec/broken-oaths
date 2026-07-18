# BrokenOaths.Game.Stewardship

Feudal + alliance stewardship core for story 910. Resolves who-may-steward-whom by reading BOTH the Game.Vassalage relationship (907) AND the existing Game.Alliance relationship (899/901): a lord and fellow vassals of the same lord may steward a household member, allies may steward each other; keeps the feudal asymmetry (lords are never stewarded by their vassals) while alliance stewardship is symmetric/mutual. Only acts while the owner is offline (Game.Presence). Actions: sweep the owner's Gold Bank (909) entirely to the owner; set the owner's production queue constructive-only from a safe whitelist (no disband/cancel-grief); emergency defensive orders on the owner's units, defensive-only and only while the owner is under attack. Every action is written to StewardLog; provable sabotage dings the steward's Honor on the Player schema.

## Type

module

## Dependencies

- BrokenOaths.Game.Vassalage
- BrokenOaths.Game.Alliance
- BrokenOaths.Game.Bank
- BrokenOaths.Game.Presence
- BrokenOaths.Game.Production
- BrokenOaths.Game.Combat
- BrokenOaths.Game.Player
- BrokenOaths.Game.StewardLog
