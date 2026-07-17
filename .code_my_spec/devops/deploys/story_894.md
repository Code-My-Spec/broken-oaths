# UAT Deploy — story 894

- **Version deployed**: 9f8056fabfa1f5f2252aadc301c8f163fc3f9a80 (batch-3 final: Camp Assault with the full combat/barbarian/city-defense/turn-length set, camp cadence + placement fixes, heir persistence, board art wiring)
- **Deployed at**: 2026-07-17T10:03:49Z via scripts/deploy-uat (GHA build succeeded, kamal deploy -d uat)
- **Migrations**: bin/migrate run post-deploy — all up through 20260717100000 (turn_seconds, city defense fields, unit tile-uniqueness drop for garrisons, barbarian camps, heir_arrives_turn).
- **Health check verified**: YES — https://uat.broken-oaths.com/health returned HTTP 200 over valid TLS at 2026-07-17T10:03:49Z.
- **QA basis**: story 894 has a passing DB-backed QA attempt (batch-3 QA phase, 2026-07-17); all medium+ issues found during QA are resolved. Prod promotion per the cycle-end release process.
