# UAT Deploy — story 901

- **Version deployed**: 2543e04f47fedf48ed6667bbae9881522c64a961 (batch-4 final: Discovering Other Players, Player-to-Player Chat, Cooperative Barbarian Fighting — plus mobile touch controls and the dev-only QA control surface)
- **Deployed at**: 2026-07-18T03:17Z via scripts/deploy-uat (GHA build succeeded, kamal deploy -d uat)
- **Migrations**: bin/migrate run post-deploy — all up through 20260717180000 (known_players, alliances, chat_conversations/messages/blocks, chat_messages.read_at, chat_messages.body widened to varchar(500), worlds.paused).
- **Health check verified**: YES — https://uat.broken-oaths.com/health returned HTTP 200 over valid TLS at 2026-07-18T03:20:38Z.
- **QA basis**: story 901 has a passing DB-backed QA attempt (batch-4 QA phase, 2026-07-18); all medium+ issues found during QA are resolved. Prod promotion completed in the same release (https://broken-oaths.com /health 200; dev-only /dev/qa routes confirmed 404 in prod).
