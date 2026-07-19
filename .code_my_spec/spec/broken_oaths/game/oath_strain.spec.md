# BrokenOaths.Game.OathStrain

Oath Strain engine (story 913). Accrues/decays the 0-100 oath_strain field on each Vassalage from grievance drivers (tribute rate, broken Protection Pact spike, refused levy) and easing drivers (gifts, autonomy, lowered tribute, shared enemy). Slow and sticky (moves over many turns, not per-tick). Exposes the strain→rebellion-army-size curve consumed by Rebellion (915). Pure logic over the Vassalage schema; visible to both lord and vassal. Behind :feudal_enabled.

## Type

module
