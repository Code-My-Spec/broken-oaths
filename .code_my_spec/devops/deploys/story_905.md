# UAT Deploy — story 905

- **Version deployed**: ae2d94026dd172fdc2e3805a670bd353026d056e (batch-5: Stone Age Technology Tree, Advancing to Bronze Age, Stone Age Progress Indicators, Tile Resources — stories 902-905. This story: Tile Resources.)
- **Deployed at**: 2026-07-18T08:52Z via scripts/deploy-uat (GHA build succeeded, kamal deploy -d uat; container reported healthy on /up).
- **Migrations**: bin/migrate run post-deploy — 5 new migrations applied, all up through 20260718060000 (game_player_research table + indexes, game_improvements.duration, game_cities.has_granary, worlds.resource_density, game_players combat counters barbarians_killed/camps_destroyed).
- **Health check verified**: YES — https://uat.broken-oaths.com/health returned HTTP 200 over valid TLS (ssl_verify=0) at 2026-07-18T08:53Z; /up and / also 200.
- **QA basis**: story 905 has a passing DB-backed QA attempt (batch-5 QA phase, 2026-07-18); all medium+ issues found during QA are resolved (879 spec math 7469, CityPanel dynamic catalog, research persistence, hills relief band for reachable Sheep/Stone). Full unit suite 794/0 at deployed SHA.
- **Prod promotion**: pending cycle-end release process (after QA journeys), per the deploy task's own instructions. Standing prod-deploy authorization on file.

## Fix redeploy (post QA-journey)

- **Version**: e0f7c40dfb0d59330528fd6699fa31c026aa1967 — redeploy after the cross-story QA journeys surfaced 3 batch-5 bugs, now fixed: critical bronze_spearman selection crash in GameLive.Play (missing UnitPanel clause), high worked-tile population-cap bypass, medium settler pop-cost masked by same-tick growth. Code-only (no new migrations).
- **Deployed at**: 2026-07-18T09:51Z via scripts/deploy-uat (GHA build succeeded, kamal deploy -d uat).
- **Health check verified**: YES — https://uat.broken-oaths.com/health HTTP 200 over valid TLS (ssl_verify=0); /up 200.
- **Suite at SHA**: 799 passing, 0 failures.
