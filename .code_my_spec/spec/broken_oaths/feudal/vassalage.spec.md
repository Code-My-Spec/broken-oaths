# BrokenOaths.Feudal.Vassalage

The player-to-player feudal relationship record, persisted via the WorldServer tick delta. Carries forward-looking fields from day one: world_id, lord_player_id, vassal_player_id, tribute_rate (default 0.25), oath_strain (0-100, default 0), hidden_agenda (enum: restore|usurp|kingmaker|merchant_prince), contract_terms (jsonb reciprocal duties), status, and Honor ledger hooks. Story 907.

## Type

schema
