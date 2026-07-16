# UAT Deploy — story 875

- **Version deployed**: 7f31c3d (branch tip — includes the full city loop: stories 878-883 core+UI, 69/69 spex green, 436 unit tests)
- **Deployed at**: 2026-07-16T11:42:57Z via kamal deploy -d uat (image ghcr.io/code-my-spec/broken_oaths, GHA build succeeded)
- **Migrations**: run explicitly post-deploy via `kamal app exec -d uat "bin/migrate"` — city-loop tables (game_cities, game_production_items, game_improvements) created and the 100-point HP rescale applied (lords 20→150, settlers 10→50).
- **Health check verified**: YES — https://uat.broken-oaths.com/health returned HTTP 200 over valid TLS at 2026-07-16T11:42:57Z, checked after deploy + migrate completed ("Finished all in 25.9 seconds", deploy lock released cleanly).
- **Notes**: prod promotion deferred to the cycle-end release process.
